import Foundation
import CoreMIDI
import SwiftUI
import OSLog

class MIDIManager: ObservableObject {
    @Published var isConnected = false
    @Published var frameBuffer: [UInt8] = Array(repeating: 0, count: 128 * 6)
    @Published var smoothingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smoothingEnabled, forKey: "smoothingEnabled")
        }
    }
    @Published var smoothingQuality: Image.Interpolation {
        didSet {
            // Store as integer
            let value: Int
            switch smoothingQuality {
            case .none: value = 0
            case .low: value = 1
            case .medium: value = 2
            case .high: value = 3
            @unknown default: value = 2
            }
            UserDefaults.standard.set(value, forKey: "smoothingQuality")
        }
    }
    @Published var isWaitingForConnection = false
    
    struct MIDIPort: Identifiable {
        let id: MIDIEndpointRef
        let name: String
    }
    
    @Published var availablePorts: [MIDIPort] = []
    @Published var selectedPort: MIDIPort? {
        didSet {
            // Immediately handle port changes
            if isConnected {
                disconnect()
            }
            clearFrameBuffer()
            if let port = selectedPort {
                lastSelectedPortName = port.name
                connectToDeluge(portName: port.name)
            }
        }
    }
    
    private var lastSelectedPortName: String? // Track last selected port
    
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
    
    private let frameQueue = DispatchQueue(label: "com.delugedisplay.framequeue")
    private var pendingFrame: [UInt8]?
    
    private let maxSysExSize = 1024 * 16 // 16KB should be plenty for OLED frames
    
    private var connectionTimer: Timer?
    
    private let logger = Logger(subsystem: "com.delugedisplay", category: "MIDIManager")
    private let delugePortName = ""
    
    private func flipByte(_ byte: UInt8) -> UInt8 {
        var flipped: UInt8 = 0
        for i in 0..<8 {
            if (byte & (1 << i)) != 0 {
                flipped |= (1 << (7 - i))
            }
        }
        return flipped
    }
    
    private func clearFrameBuffer() {
        DispatchQueue.main.async {
            self.frameBuffer = Array(repeating: 0, count: self.expectedFrameSize)
        }
    }
    
    private func drawWaitingMessage() {
        // This is a placeholder - we'll need to implement the actual text drawing
        // For now, just setting the first few bytes to indicate activity
        DispatchQueue.main.async {
            var newBuffer = Array(repeating: UInt8(0), count: self.expectedFrameSize)
            // Set some pixels in the first row to show activity
            newBuffer[0] = 0xFF
            newBuffer[1] = 0xFF
            self.frameBuffer = newBuffer
        }
    }
    
    init() {
        // Load saved preferences or use defaults
        self.smoothingEnabled = UserDefaults.standard.bool(forKey: "smoothingEnabled")
        
        // Convert stored integer back to Interpolation
        let savedQuality = UserDefaults.standard.integer(forKey: "smoothingQuality")
        self.smoothingQuality = switch savedQuality {
            case 0: .none
            case 1: .low
            case 3: .high
            default: .medium
        }
    }
    
    deinit {
        disconnect()
    }
    
    private func scanAvailablePorts() {
        var ports: [MIDIPort] = []
        
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            if let n = name?.takeUnretainedValue() as String? {
                ports.append(MIDIPort(id: endpoint, name: n))
                
                // Only auto-select Port 3 if no port was previously selected
                if n.contains(delugePortName) && selectedPort == nil && lastSelectedPortName == nil {
                    DispatchQueue.main.async {
                        self.selectedPort = MIDIPort(id: endpoint, name: n)
                    }
                }
                
                // If this is the last selected port, reselect it
                if let lastPort = lastSelectedPortName, n == lastPort {
                    DispatchQueue.main.async {
                        self.selectedPort = MIDIPort(id: endpoint, name: n)
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            self.availablePorts = ports
        }
    }
    
    func setupMIDI() {
        var status = MIDIClientCreateWithBlock("DelugeDisplay" as CFString, &client) { [weak self] _ in
            // Only log significant MIDI system changes
            self?.logger.info("MIDI system changed - rescanning ports")
            self?.scanAvailablePorts()
        }
        guard status == noErr else {
            logger.error("Failed to create MIDI client: \(status)")
            return
        }
        
        status = MIDIInputPortCreateWithBlock(client, "Input" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.handleMIDIPacketList(packetList.pointee)
        }
        guard status == noErr else {
            logger.error("Failed to create input port: \(status)")
            return
        }
        
        status = MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)
        guard status == noErr else {
            logger.error("Failed to create output port: \(status)")
            return
        }
        
        scanAvailablePorts()
        startConnectionTimer()
    }
    
    private func connectToDeluge(portName: String) {
        lastSelectedPortName = portName
        
        guard client != 0, inputPort != 0, outputPort != 0 else {
            setupMIDI()
            return
        }
        
        delugeInput = nil
        delugeOutput = nil
        isConnected = false
        clearFrameBuffer()
        
        // Find matching input/output pair
        var foundOutput: MIDIEndpointRef?
        var foundInput: MIDIEndpointRef?
        
        // First find output
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            if let n = name?.takeUnretainedValue() as String?, n == portName {
                foundOutput = endpoint
                break
            }
        }
        
        // Then find input
        for i in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            if let n = name?.takeUnretainedValue() as String?, n == portName {
                foundInput = endpoint
                break
            }
        }
        
        // Only proceed if we found both
        if let input = foundInput, let output = foundOutput {
            delugeInput = input
            delugeOutput = output
            
            MIDIPortConnectSource(inputPort, input, nil)
            startUpdateTimer()
        } else {
            isConnected = false
            return
        }
    }
    
    private func startConnectionTimer() {
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  !self.isConnected,
                  let port = self.selectedPort,
                  port.name == self.lastSelectedPortName else { return }
            
            // Don't retry if ports aren't found
            if self.delugeInput == nil || self.delugeOutput == nil {
                return
            }
            
            self.connectToDeluge(portName: port.name)
        }
    }
    
    func disconnect() {
        // Only log disconnects from active Deluge connections
        if isConnected {
            logger.info("Disconnected from Deluge on port: \(self.lastSelectedPortName ?? "unknown")")
        }
        
        connectionTimer?.invalidate()
        connectionTimer = nil
        updateTimer?.invalidate()
        updateTimer = nil
        
        if let input = delugeInput {
            MIDIPortDisconnectSource(inputPort, input)
        }
        
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
        
        delugeInput = nil
        delugeOutput = nil
        isConnected = false
        fullFrameInitialized = false
        clearFrameBuffer()
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
            
            guard newFrame.count == 128 * 6 else {
                logger.error("Invalid frame size in update: \(newFrame.count)")
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
        
        guard length > 0, length <= maxSysExSize else {
            logger.error("Invalid MIDI packet length: \(length)")
            return
        }
        
        let bytes = withUnsafeBytes(of: packet.pointee.data) { buffer in
            Array(buffer.prefix(length))
        }
        
        for byte in bytes {
            if sysExBuffer.count >= maxSysExSize {
                logger.warning("SysEx buffer overflow, clearing")
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
        guard bytes.count >= 7,
              bytes.count <= maxSysExSize,
              bytes[0] == 0xf0,
              bytes[1] == 0x7d,
              bytes[2] == 0x02,
              bytes[3] == 0x40 else {
            return
        }
        
        let messageType = bytes[4]
        
        guard bytes.count >= 7,
              bytes.last == 0xf7 else {
            return
        }
        
        let body = Array(bytes[6...(bytes.count - 2)])
        
        if messageType == 0x01 {
            do {
                let (unpacked, _) = try unpack7to8RLE(body, maxBytes: expectedFrameSize)
                guard unpacked.count == expectedFrameSize else {
                    logger.error("Invalid frame size: \(unpacked.count)")
                    return
                }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if !self.isConnected {
                        // Only log when we first start receiving valid OLED data
                        self.logger.info("Connected to Deluge on port: \(self.lastSelectedPortName ?? "unknown")")
                    }
                    self.isConnected = true
                    self.frameBuffer = unpacked
                }
            } catch {
                logger.error("Frame decode error: \(error.localizedDescription)")
            }
        }
    }
}
