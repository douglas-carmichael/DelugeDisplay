import Foundation
import CoreMIDI

class MIDIManager: ObservableObject {
    @Published var isConnected = false
    @Published var frameBuffer: [UInt8] = Array(repeating: 0, count: 128 * 6)
    
    private let expectedFrameSize = 128 * 6
    private let frameTimeout: TimeInterval = 0.1
    private let maxDeltaFails = 3
    
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0
    private var delugeInput: MIDIEndpointRef?
    private var delugeOutput: MIDIEndpointRef?
    private var sysExBuffer: [UInt8] = []
    private var fullFrameInitialized = false
    private var updateTimer: Timer?
    private var fullFrameTimer: Timer?
    private var lastFrameTime = Date()
    private var deltaFailCount = 0
    
    private let screenWidth = 128
    private let screenHeight = 48
    private let bytesPerRow = 128
    private let numRows = 6
    
    private let oledRequestSysex: [UInt8] = [0xf0, 0x7d, 0x02, 0x00, 0x02, 0xf7]
    private let delugePortName = "Port 3"
    
    private let frameQueue = DispatchQueue(label: "com.delugedisplay.framequeue")
    private var pendingFrame: [UInt8]?
    
    private let maxSysExSize = 1024 * 16 // 16KB should be plenty for OLED frames
    
    private func flipByte(_ byte: UInt8) -> UInt8 {
        var flipped: UInt8 = 0
        for i in 0..<8 {
            if (byte & (1 << i)) != 0 {
                flipped |= (1 << (7 - i))
            }
        }
        return flipped
    }
    
    deinit {
        disconnect()
    }
    
    func setupMIDI() {
        var status = MIDIClientCreateWithBlock("DelugeDisplay" as CFString, &client) { _ in }
        guard status == noErr else {
            print("Failed to create MIDI client")
            return
        }
        
        status = MIDIInputPortCreateWithBlock(client, "Input" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.handleMIDIPacketList(packetList.pointee)
        }
        guard status == noErr else {
            print("Failed to create input port")
            return
        }
        
        status = MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)
        guard status == noErr else {
            print("Failed to create output port")
            return
        }
        
        connectToDeluge(delugePortName: "Port 3")
    }
    
    private func connectToDeluge(delugePortName:String) {
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            if let n = name?.takeUnretainedValue() as String?, n.contains(delugePortName) {
                delugeOutput = endpoint
            }
        }
        
        for i in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            if let n = name?.takeUnretainedValue() as String?, n.contains(delugePortName) {
                delugeInput = endpoint
            }
        }
        
        guard let input = delugeInput, let _ = delugeOutput else {  
            print("Could not find specified port")
            return
        }
        
        MIDIPortConnectSource(inputPort, input, nil)
        
        startUpdateTimer()
        
        isConnected = true
    }
    
    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.requestFullFrame()
        }
    }
    
    private func checkFrameTimeout() {
        if Date().timeIntervalSince(lastFrameTime) > frameTimeout {
            requestFullFrame()
        }
    }
    
    private func updateFrameBuffer(_ newFrame: [UInt8]) {
        frameQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Validate frame size
            guard newFrame.count == 128 * 6 else {
                print("Invalid frame size in update: \(newFrame.count)")
                return
            }
            
            DispatchQueue.main.async {
                self.frameBuffer = newFrame
                self.lastFrameTime = Date()
            }
        }
    }
    
    private func requestFullFrame() {
        sendSysEx([0xf0, 0x7d, 0x02, 0x00, 0x01, 0xf7])
    }
    
    private func sendSysEx(_ data: [UInt8]) {
        guard let output = delugeOutput else { return }
        
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        _ = MIDIPacketListAdd(&packetList, 1024, packet, 0, data.count, data)
        MIDISend(outputPort, output, &packetList)
    }
    
    private func handleMIDIPacketList(_ packetList: MIDIPacketList) {
        var packet = packetList.packet
        for _ in 0..<packetList.numPackets {
            handleMIDIPacket(&packet)
            packet = MIDIPacketNext(&packet).pointee
        }
    }
    
    private func handleMIDIPacket(_ packet: UnsafePointer<MIDIPacket>) {
        let length = Int(packet.pointee.length)
        
        // Safety check for packet length
        guard length > 0, length <= maxSysExSize else {
            print("Invalid MIDI packet length: \(length)")
            return
        }
        
        // Use withUnsafeBytes for safe memory access
        let bytes = withUnsafeBytes(of: packet.pointee.data) { buffer in
            Array(buffer.prefix(length))
        }
        
        for byte in bytes {
            if sysExBuffer.count >= maxSysExSize {
                print("SysEx buffer overflow, clearing")
                sysExBuffer.removeAll()
                return
            }
            sysExBuffer.append(byte)
            if byte == 0xf7 {
                processSysEx(sysExBuffer)
                sysExBuffer.removeAll()
            }
        }
    }
    
    private func processSysEx(_ bytes: [UInt8]) {
        // Additional safety checks
        guard bytes.count >= 7,
              bytes.count <= maxSysExSize,
              bytes[0] == 0xf0,
              bytes[1] == 0x7d,
              bytes[2] == 0x02,
              bytes[3] == 0x40 else {
            return
        }
        
        let messageType = bytes[4]
        
        // Safety check for body extraction
        guard bytes.count >= 7,
              bytes.last == 0xf7 else {
            return
        }
        
        let body = Array(bytes[6...(bytes.count - 2)])
        
        if messageType == 0x01 { // Full frame only
            do {
                let (unpacked, _) = try unpack7to8RLE(body, maxBytes: expectedFrameSize)
                guard unpacked.count == expectedFrameSize else {
                    print("Invalid frame size: \(unpacked.count)")
                    return
                }
                
                DispatchQueue.main.async { [weak self] in
                    self?.frameBuffer = unpacked
                }
            } catch {
                print("Frame decode error: \(error)")
            }
        }
    }
    
    func disconnect() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
            outputPort = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
        isConnected = false
        fullFrameInitialized = false
    }
}
