import Foundation
import CoreMIDI

class MIDIManager: ObservableObject {
    @Published var isConnected = false
    @Published var frameBuffer: [UInt8] = Array(repeating: 0, count: 128 * 6)
    
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0
    private var delugeInput: MIDIEndpointRef?
    private var delugeOutput: MIDIEndpointRef?
    private var sysExBuffer: [UInt8] = []
    private var fullFrameInitialized = false
    private var updateTimer: Timer?
    
    private let delugePortName = "Port 3"
    private let oledRequestSysex: [UInt8] = [0xf0, 0x7d, 0x02, 0x00, 0x02, 0xf7] // Changed to request delta updates
    
    deinit {
        disconnect()
    }
    
    func setupMIDI() {
        // Create MIDI client
        var status = MIDIClientCreateWithBlock("DelugeDisplay" as CFString, &client) { _ in }
        guard status == noErr else {
            print("Failed to create MIDI client")
            return
        }
        
        // Create input port
        status = MIDIInputPortCreateWithBlock(client, "Input" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.handleMIDIPacketList(packetList.pointee)
        }
        guard status == noErr else {
            print("Failed to create input port")
            return
        }
        
        // Create output port
        status = MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)
        guard status == noErr else {
            print("Failed to create output port")
            return
        }
        
        connectToDeluge()
    }
    
    private func connectToDeluge() {
        // Find Deluge ports
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
        
        guard let input = delugeInput, let output = delugeOutput else {
            print("Could not find Deluge Port 3")
            return
        }
        
        MIDIPortConnectSource(inputPort, input, nil)
        
        // Request initial full frame
        sendSysEx([0xf0, 0x7d, 0x02, 0x00, 0x01, 0xf7])
        
        // Start update timer
        startUpdateTimer()
        
        isConnected = true
    }
    
    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.sendOLEDRequest()
        }
    }
    
    private func sendSysEx(_ data: [UInt8]) {
        guard let output = delugeOutput else { return }
        
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        _ = MIDIPacketListAdd(&packetList, 1024, packet, 0, data.count, data)
        MIDISend(outputPort, output, &packetList)
    }
    
    private func sendOLEDRequest() {
        sendSysEx(oledRequestSysex)
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
        let bytePtr = withUnsafeBytes(of: packet.pointee.data) {
            $0.bindMemory(to: UInt8.self).prefix(length)
        }
        let bytes = Array(bytePtr)
        
        for byte in bytes {
            sysExBuffer.append(byte)
            if byte == 0xf7 {
                processSysEx(sysExBuffer)
                sysExBuffer.removeAll()
            }
        }
    }
    
    private func processSysEx(_ bytes: [UInt8]) {
        guard bytes.count >= 7 else { return }
        guard bytes[0] == 0xf0, bytes[1] == 0x7d, bytes[2] == 0x02, bytes[3] == 0x40 else { return }
        
        let messageType = bytes[4]
        let body = Array(bytes[6..<bytes.count - 1])
        
        switch messageType {
        case 0x01: // Full frame
            do {
                let (unpacked, _) = try unpack7to8RLE(body, maxBytes: body.count)
                guard unpacked.count == 768 else {
                    print("Invalid full frame size: \(unpacked.count)")
                    return
                }
                DispatchQueue.main.async {
                    self.frameBuffer = unpacked
                    self.fullFrameInitialized = true
                }
            } catch {
                print("Full frame decode failed: \(error)")
            }
            
        case 0x02: // Delta frame
            guard fullFrameInitialized else { return }
            do {
                var buffer = frameBuffer
                try applyDeltaRLE(body, to: &buffer)
                DispatchQueue.main.async {
                    self.frameBuffer = buffer
                }
            } catch {
                // Request a full frame refresh if delta update fails
                sendSysEx([0xf0, 0x7d, 0x02, 0x00, 0x01, 0xf7])
            }
            
        default:
            break
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
