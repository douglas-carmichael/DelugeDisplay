import Foundation
import CoreMIDI
import SwiftUI
import OSLog

class MIDIManager: ObservableObject {
    @Published var isConnected = false
    @Published var frameBuffer: [UInt8] = []
    @Published var smoothingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smoothingEnabled, forKey: "smoothingEnabled")
        }
    }
    @Published var smoothingQuality: Image.Interpolation {
        didSet {
            // Store interpolation as integer
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
    @Published var availablePorts: [MIDIPort] = []
    @Published var selectedPort: MIDIPort? {
        didSet {
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
    @Published var displayColorMode: DelugeDisplayColorMode {
        didSet {
            UserDefaults.standard.set(displayColorMode.rawValue, forKey: "displayColorMode")
        }
    }
    
    struct MIDIPort: Identifiable {
        let id: MIDIEndpointRef
        let name: String
    }
    
    private var lastSelectedPortName: String? {
        didSet {
            if let name = lastSelectedPortName {
                UserDefaults.standard.set(name, forKey: "lastSelectedPort")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastSelectedPort")
            }
        }
    }
    
    private let processQueue = DispatchQueue(label: "com.delugedisplay.process", qos: .userInteractive)
    private let frameUpdateQueue = DispatchQueue(label: "com.delugedisplay.frame", qos: .userInteractive)
    private let expectedFrameSize = 128 * 6
    private let frameTimeout: TimeInterval = 0.2
    private let maxDeltaFails = 3
    private let maxSysExSize = 1024 * 32
    private let screenWidth = 128
    private let screenHeight = 48
    private let bytesPerRow = 128
    private let numRows = 6
    private let logger = Logger(subsystem: "com.delugedisplay", category: "MIDIManager")
    private let delugePortName = ""
    private let frameQueue = DispatchQueue(label: "com.delugedisplay.framequeue")
    private let updateInterval: TimeInterval = 0.05
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0
    private var delugeInput: MIDIEndpointRef?
    private var delugeOutput: MIDIEndpointRef?
    private var sysExBuffer: [UInt8] = []
    private var updateTimer: Timer?
    private var connectionTimer: Timer?
    private var lastPacketTime = Date()
    private var isProcessingSysEx = false
    private var lastScanTime: Date = Date()
    private let minimumScanInterval: TimeInterval = 1.0 // Minimum time between scans
    
    init() {
        // Load saved preferences
        self.smoothingEnabled = UserDefaults.standard.bool(forKey: "smoothingEnabled")
        
        // Load interpolation from stored integer
        let interpolationValue = UserDefaults.standard.integer(forKey: "smoothingQuality")
        switch interpolationValue {
        case 0: self.smoothingQuality = .none
        case 1: self.smoothingQuality = .low
        case 2: self.smoothingQuality = .medium
        case 3: self.smoothingQuality = .high
        default: self.smoothingQuality = .medium
        }
        
        if let savedMode = UserDefaults.standard.string(forKey: "displayColorMode"),
           let mode = DelugeDisplayColorMode(rawValue: savedMode) {
            self.displayColorMode = mode
        } else {
            self.displayColorMode = .normal
        }
        self.lastSelectedPortName = UserDefaults.standard.string(forKey: "lastSelectedPort")
        setupMIDI()
    }
    
    deinit {
        disconnect()
    }
    
    func setupMIDI() {
        var status = MIDIClientCreateWithBlock("DelugeDisplay" as CFString, &client) { [weak self] _ in
            guard let self = self else { return }
            
            // Only scan if enough time has passed since last scan
            let now = Date()
            if now.timeIntervalSince(self.lastScanTime) >= self.minimumScanInterval {
                self.logger.info("MIDI system changed - rescanning ports")
                self.scanAvailablePorts()
                self.lastScanTime = now
            }
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
    
    private func scanAvailablePorts() {
        var ports: [MIDIPort] = []
        
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            if let n = name?.takeUnretainedValue() as String? {
                ports.append(MIDIPort(id: endpoint, name: n))
                
                if n.contains(self.delugePortName) && self.selectedPort == nil && self.lastSelectedPortName == nil {
                    DispatchQueue.main.async { [weak self] in
                        self?.selectedPort = MIDIPort(id: endpoint, name: n)
                    }
                }
                
                if let lastPort = self.lastSelectedPortName, n == lastPort {
                    DispatchQueue.main.async { [weak self] in
                        self?.selectedPort = MIDIPort(id: endpoint, name: n)
                    }
                }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.availablePorts = ports
        }
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
        
        var foundOutput: MIDIEndpointRef?
        var foundInput: MIDIEndpointRef?
        
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            if let n = name?.takeUnretainedValue() as String?, n == portName {
                foundOutput = endpoint
                break
            }
        }
        
        for i in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            if let n = name?.takeUnretainedValue() as String?, n == portName {
                foundInput = endpoint
                break
            }
        }
        
        if let input = foundInput, let output = foundOutput {
            delugeInput = input
            delugeOutput = output
            
            MIDIPortConnectSource(inputPort, input, nil)
            startUpdateTimer()
            
            requestFullFrame()
        }
    }
    
    private func startConnectionTimer() {
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  !self.isConnected,
                  let port = self.selectedPort,
                  port.name == self.lastSelectedPortName else { return }
            
            if self.delugeInput == nil || self.delugeOutput == nil {
                self.connectToDeluge(portName: port.name)
            } else {
                self.requestFullFrame()
            }
        }
    }
    
    func disconnect() {
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
        clearFrameBuffer()
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
            sysExBuffer.removeAll()
            isProcessingSysEx = false
            return
        }
        
        let bytes = withUnsafeBytes(of: packet.pointee.data) { buffer in
            Array(buffer.prefix(length))
        }
        
        processQueue.async { [weak self] in
            guard let self = self else { return }
            
            for byte in bytes {
                if byte == 0xf0 {
                    self.sysExBuffer.removeAll()
                    self.sysExBuffer.append(byte)
                    self.isProcessingSysEx = true
                } else if byte == 0xf7 && self.isProcessingSysEx {
                    self.sysExBuffer.append(byte)
                    self.processSysEx(self.sysExBuffer)
                    self.sysExBuffer.removeAll()
                    self.isProcessingSysEx = false
                } else if self.isProcessingSysEx {
                    if self.sysExBuffer.count < self.maxSysExSize {
                        self.sysExBuffer.append(byte)
                    } else {
                        self.sysExBuffer.removeAll()
                        self.isProcessingSysEx = false
                        self.logger.error("SysEx buffer overflow")
                    }
                }
            }
            
            self.lastPacketTime = Date()
        }
    }
    
    private func processSysEx(_ bytes: [UInt8]) {
        guard bytes.count >= 7,
              bytes[0] == 0xf0,
              bytes[1] == 0x7d,
              bytes[2] == 0x02,
              bytes[3] == 0x40,
              bytes.last == 0xf7 else {
            return
        }
        
        let messageType = bytes[4]
        let body = Array(bytes[6...(bytes.count - 2)])
        
        if messageType == 0x01 {
            do {
                let (unpacked, _) = try unpack7to8RLE(body, maxBytes: expectedFrameSize)
                guard unpacked.count == expectedFrameSize else {
                    return
                }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if !self.isConnected {
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
    
    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.requestFullFrameIfNecessary()
        }
    }
    
    private func requestFullFrameIfNecessary() {
        processQueue.async { [weak self] in
            guard let self = self else { return }
            if Date().timeIntervalSince(self.lastPacketTime) > self.updateInterval {
                self.requestFullFrame()
            }
        }
    }
    
    private func requestFullFrame() {
        processQueue.async { [weak self] in
            guard let self = self else { return }
            self.sendSysEx([0xf0, 0x7d, 0x02, 0x00, 0x01, 0xf7])
        }
    }
    
    private func sendSysEx(_ data: [UInt8]) {
        guard let output = delugeOutput else { return }
        
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        _ = MIDIPacketListAdd(&packetList, 1024, packet, 0, data.count, data)
        MIDISend(outputPort, output, &packetList)
    }
    
    private func clearFrameBuffer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.frameBuffer = Array(repeating: 0, count: self.expectedFrameSize)
        }
    }
}
