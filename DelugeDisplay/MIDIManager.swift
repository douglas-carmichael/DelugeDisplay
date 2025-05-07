import Foundation
import CoreMIDI
import SwiftUI
import OSLog

class MIDIManager: ObservableObject {
    @Published var isConnected = false
    @Published var frameBuffer: [UInt8] = []
    @Published var sevenSegmentDigits: [UInt8] = [0, 0, 0, 0]
    @Published var sevenSegmentDots: UInt8 = 0
    @Published var smoothingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smoothingEnabled, forKey: "smoothingEnabled")
        }
    }
    @Published var smoothingQuality: Image.Interpolation {
        didSet {
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
            clearSevenSegmentData()
            if let port = selectedPort {
                lastSelectedPortName = port.name
                connectToDeluge(portName: port.name)
            } else {
                lastSelectedPortName = nil
            }
        }
    }
    @Published var displayColorMode: DelugeDisplayColorMode {
        didSet {
            UserDefaults.standard.set(displayColorMode.rawValue, forKey: "displayColorMode")
        }
    }
    @Published var displayMode: DelugeDisplayMode = .oled {
        didSet {
            if oldValue != displayMode {
                logger.info("Display mode changed to: \(self.displayMode.rawValue)")
                sendDisplayToggleCommand()
                requestDisplayData()
            }
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
    private let expectedSevenSegmentDataLength = 5
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
    private let minimumScanInterval: TimeInterval = 1.0
    private let sysExRequestOLED: [UInt8] = [0xf0, 0x7d, 0x02, 0x00, 0x01, 0xf7]
    private let sysExRequestSevenSegment: [UInt8] = [0xf0, 0x7d, 0x02, 0x01, 0x00, 0xf7]
    private let sysExToggleDisplayScreen: [UInt8] = [0xf0, 0x7d, 0x02, 0x00, 0x04, 0xf7]
    
    init() {
        self.smoothingEnabled = UserDefaults.standard.bool(forKey: "smoothingEnabled")
        
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
        if let savedDisplayMode = UserDefaults.standard.string(forKey: "displayMode"),
           let mode = DelugeDisplayMode(rawValue: savedDisplayMode) {
            self.displayMode = mode
        } else {
            self.displayMode = .oled
        }
        
        setupMIDI()
    }
    
    deinit {
        disconnect()
    }
    
    func setupMIDI() {
        var status = MIDIClientCreateWithBlock("DelugeDisplay" as CFString, &client) { [weak self] notificationPtr in 
            guard let self = self else { return }
            
            let now = Date()
            if now.timeIntervalSince(self.lastScanTime) >= self.minimumScanInterval {
                self.logger.info("MIDI system changed - rescanning ports. Notification: \(notificationPtr.pointee.messageID.rawValue)")
                self.scanAvailablePorts()
                self.lastScanTime = now
                
                if let selectedPortName = self.lastSelectedPortName, self.delugeInput == nil || self.delugeOutput == nil {
                    if self.availablePorts.contains(where: { $0.name == selectedPortName }) {
                        self.logger.info("Previously selected port \(selectedPortName) might be available again. Attempting to reconnect.")
                        if let portToSelect = self.availablePorts.first(where: { $0.name == selectedPortName }) {
                            DispatchQueue.main.async {
                                self.selectedPort = portToSelect
                            }
                        }
                    }
                }
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
        var autoSelected = false
        
        logger.debug("Scanning for available MIDI ports...")
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            if let n = name?.takeUnretainedValue() as String? {
                logger.debug("Found output port: \(n) (ID: \(endpoint))")
                ports.append(MIDIPort(id: endpoint, name: n))
                
                if !self.delugePortName.isEmpty && n.contains(self.delugePortName) && self.selectedPort == nil && self.lastSelectedPortName == nil && !autoSelected {
                    logger.info("Auto-selecting port based on delugePortName: \(n)")
                    DispatchQueue.main.async { [weak self] in
                        self?.selectedPort = MIDIPort(id: endpoint, name: n)
                        autoSelected = true
                    }
                }
                
                if let lastPortName = self.lastSelectedPortName, n == lastPortName {
                    logger.info("Re-selecting last used port: \(n)")
                    DispatchQueue.main.async { [weak self] in
                        if self?.selectedPort?.name != n {
                            self?.selectedPort = MIDIPort(id: endpoint, name: n)
                        }
                    }
                }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let oldPorts = self.availablePorts.map { $0.name }.sorted()
            let newPorts = ports.map { $0.name }.sorted()
            if oldPorts != newPorts {
                self.availablePorts = ports
                self.logger.info("Available MIDI ports updated: \(ports.map { $0.name })")
            }
            
            if self.selectedPort == nil && self.lastSelectedPortName != nil {
                if !ports.contains(where: { $0.name == self.lastSelectedPortName }) {
                    self.logger.warning("Last selected port '\(self.lastSelectedPortName!)' is no longer available.")
                }
            }
        }
    }
    
    private func connectToDeluge(portName: String) {
        logger.info("Attempting to connect to Deluge on port: \(portName)")
        
        guard client != 0, inputPort != 0, outputPort != 0 else {
            logger.warning("MIDI client/ports not initialized. Attempting to re-setup MIDI.")
            setupMIDI()
            return
        }
        
        if let currentInput = delugeInput {
            logger.debug("Disconnecting from previous input source.")
            MIDIPortDisconnectSource(inputPort, currentInput)
        }
        
        delugeInput = nil
        delugeOutput = nil
        clearFrameBuffer()
        clearSevenSegmentData()
        
        var foundOutput: MIDIEndpointRef?
        var foundInput: MIDIEndpointRef?
        
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            var nameCF: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameCF)
            if let n = nameCF?.takeUnretainedValue() as String?, n == portName {
                foundOutput = endpoint
                logger.debug("Found matching output endpoint: \(n) (ID: \(endpoint))")
                break
            }
        }
        
        for i in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(i)
            var nameCF: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameCF)
            if let n = nameCF?.takeUnretainedValue() as String?, n == portName {
                foundInput = endpoint
                logger.debug("Found matching input endpoint: \(n) (ID: \(endpoint))")
                break
            }
        }
        
        if let input = foundInput, let output = foundOutput {
            delugeInput = input
            delugeOutput = output
            
            let status = MIDIPortConnectSource(inputPort, input, nil)
            if status == noErr {
                logger.info("Successfully connected MIDI source for port: \(portName)")
                startUpdateTimer()
                
                logger.info("Requesting initial display data for mode: \(self.displayMode.rawValue)")
                if displayMode == .oled {
                    sendDisplayToggleCommand()
                }
                requestDisplayData()
            } else {
                logger.error("Failed to connect MIDI source for port \(portName). Error: \(status)")
                delugeInput = nil
                delugeOutput = nil
            }
        } else {
            logger.error("Could not find both input and output endpoints for port: \(portName)")
        }
    }
    
    private func startConnectionTimer() {
        connectionTimer?.invalidate()
        guard lastSelectedPortName != nil || selectedPort != nil else {
            logger.info("No port selected or previously selected. Connection timer not started.")
            return
        }
        
        logger.debug("Starting connection timer.")
        isWaitingForConnection = true
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.isConnected {
                if self.isWaitingForConnection {
                    self.logger.info("Connection established. Stopping explicit connection attempts by timer.")
                    self.isWaitingForConnection = false
                }
                return
            }
            
            if !self.isWaitingForConnection {
                self.isWaitingForConnection = true
            }
            
            guard let portNameToConnect = self.selectedPort?.name ?? self.lastSelectedPortName else {
                return
            }
            
            self.logger.info("Connection timer fired. Attempting to connect/reconnect to: \(portNameToConnect)")
            
            if self.delugeInput == nil || self.delugeOutput == nil {
                self.logger.debug("Connection timer: Endpoints not set for \(portNameToConnect). Calling connectToDeluge.")
                self.connectToDeluge(portName: portNameToConnect)
            } else {
                self.logger.debug("Connection timer: Endpoints set for \(portNameToConnect), but not connected. Requesting display data.")
                self.requestDisplayData()
            }
        }
    }
    
    func disconnect() {
        let portNameToLog = selectedPort?.name ?? lastSelectedPortName ?? "unknown"
        if isConnected {
            logger.info("Disconnecting from Deluge on port: \(portNameToLog)")
        } else {
            logger.info("Ensuring MIDI resources are released for port: \(portNameToLog)")
        }
        
        connectionTimer?.invalidate()
        connectionTimer = nil
        updateTimer?.invalidate()
        updateTimer = nil
        
        if let input = delugeInput, inputPort != 0 {
            MIDIPortDisconnectSource(inputPort, input)
            logger.debug("Disconnected source for port \(portNameToLog).")
        }
        
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
            logger.debug("Disposed input port.")
        }
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
            outputPort = 0
            logger.debug("Disposed output port.")
        }
        if client != 0 {
            client = 0
            logger.debug("Disposed MIDI client.")
        }
        
        delugeInput = nil
        delugeOutput = nil
        isConnected = false
        isWaitingForConnection = false
        clearFrameBuffer()
        clearSevenSegmentData()
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
        
        guard length > 0, length <= self.maxSysExSize else {
            if length > self.maxSysExSize {
                logger.error("Received MIDI packet larger than maxSysExSize (\(length) > \(self.maxSysExSize)). Flushing buffer.")
            }
            sysExBuffer.removeAll()
            isProcessingSysEx = false
            return
        }
        
        let bytes = withUnsafeBytes(of: packet.pointee.data) { bufferPointer in
            Array(bufferPointer.prefix(length))
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
                    self.processSysExMessage(self.sysExBuffer)
                    self.sysExBuffer.removeAll()
                    self.isProcessingSysEx = false
                } else if self.isProcessingSysEx {
                    if self.sysExBuffer.count < self.maxSysExSize {
                        self.sysExBuffer.append(byte)
                    } else {
                        self.logger.error("SysEx buffer overflow. Max size: \(self.maxSysExSize). Discarding message.")
                        self.sysExBuffer.removeAll()
                        self.isProcessingSysEx = false
                    }
                }
            }
            
            if self.isConnected || self.isWaitingForConnection {
                self.lastPacketTime = Date()
            }
        }
    }
    
    private func processSysExMessage(_ bytes: [UInt8]) {
        guard bytes.count >= 5,
              bytes[0] == 0xf0,
              bytes[1] == 0x7d else {
            return
        }
        
        if bytes.count >= 7 && bytes[2] == 0x02 && bytes[3] == 0x40 && bytes.last == 0xf7 {
            let oledMessageType = bytes[4]
            let oledBody = Array(bytes[6...(bytes.count - 2)])
            
            if oledMessageType == 0x01 {
                do {
                    let (unpacked, _) = try unpack7to8RLE(oledBody, maxBytes: expectedFrameSize)
                    guard unpacked.count == expectedFrameSize else {
                        logger.error("Decoded OLED data size mismatch. Expected \(self.expectedFrameSize), got \(unpacked.count)")
                        return
                    }
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if !self.isConnected {
                            self.logger.info("OLED data received. Connected to Deluge on port: \(self.selectedPort?.name ?? self.lastSelectedPortName ?? "unknown")")
                        }
                        self.isConnected = true
                        self.isWaitingForConnection = false
                        self.frameBuffer = unpacked
                    }
                } catch {
                    logger.error("OLED frame decode error: \(error.localizedDescription). Data: \(oledBody.map { String(format: "%02X", $0) }.joined(separator: " "))")
                }
            } else if oledMessageType == 0x02 {
                logger.debug("Received OLED delta frame. Delta updates are not yet implemented.")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if !self.isConnected {
                        self.logger.info("OLED delta data received. Connected to Deluge on port: \(self.selectedPort?.name ?? self.lastSelectedPortName ?? "unknown")")
                    }
                    self.isConnected = true
                    self.isWaitingForConnection = false
                }
            } else {
                logger.warning("Received unknown OLED message type: \(String(format:"0x%02X", oledMessageType))")
            }
        } else if bytes.count == 12 && bytes[2] == 0x02 && bytes[3] == 0x41 && bytes.last == 0xf7 {
            let dots = bytes[6]
            let digits = [bytes[7], bytes[8], bytes[9], bytes[10]]
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !self.isConnected {
                    self.logger.info("7-Segment data received. Connected to Deluge on port: \(self.selectedPort?.name ?? self.lastSelectedPortName ?? "unknown")")
                }
                self.isConnected = true
                self.isWaitingForConnection = false
                self.sevenSegmentDigits = digits
                self.sevenSegmentDots = dots
            }
        } else if bytes.count >= 7 && bytes[2] == 0x03 && bytes[3] == 0x40 && bytes.last == 0xf7 {
            let msgbuf = bytes[5..<(bytes.count-1)]
            if let message = String(bytes: msgbuf, encoding: .ascii) {
                logger.debug("Deluge Debug: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                logger.debug("Deluge Debug (non-ASCII): \(msgbuf.map { String(format: "%02X", $0) }.joined(separator: " "))")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !self.isConnected { self.isConnected = true; self.isWaitingForConnection = false }
            }
        } else if bytes.count == 4 && bytes[2] == 0x00 && bytes.last == 0xf7 {
            logger.info("Received Ping response from Deluge.")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !self.isConnected { self.isConnected = true; self.isWaitingForConnection = false }
            }
        } else {
            logger.debug("Received other/unhandled SysEx message (Cmd: \(String(format:"0x%02X", bytes[2])), SubCmd: \(String(format:"0x%02X", bytes[3]))): \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
    }
    
    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.requestDisplayDataIfNecessary()
        }
    }
    
    private func requestDisplayDataIfNecessary() {
        processQueue.async { [weak self] in
            guard let self = self else { return }
            if (self.isConnected || self.isWaitingForConnection) && Date().timeIntervalSince(self.lastPacketTime) > self.updateInterval {
                self.requestDisplayData()
            }
        }
    }
    
    private func requestDisplayData() {
        processQueue.async { [weak self] in
            guard let self = self else { return }
            switch self.displayMode {
            case .oled:
                self.logger.debug("Requesting OLED display data.")
                self.sendSysEx(self.sysExRequestOLED)
            case .sevenSegment:
                self.logger.debug("Requesting 7-segment display data.")
                self.sendSysEx(self.sysExRequestSevenSegment)
            }
        }
    }
    
    private func sendDisplayToggleCommand() {
        processQueue.async { [weak self] in
            guard let self = self else { return }
            self.logger.info("Sending display toggle command to Deluge.")
            self.sendSysEx(self.sysExToggleDisplayScreen)
        }
    }
    
    private func sendSysEx(_ data: [UInt8]) {
        guard let output = delugeOutput else {
            return
        }
        
        var packetList = MIDIPacketList()
        let currentPacketPtr = MIDIPacketListInit(&packetList) 
        
        _ = MIDIPacketListAdd(&packetList, 
                              1024, 
                              currentPacketPtr, 
                              0, 
                              data.count, 
                              data)
        
        let sendStatus: OSStatus = MIDISend(outputPort, output, &packetList)
        
        if sendStatus != noErr {
            logger.error("Failed to send SysEx data. MIDISend returned error code: \(sendStatus). Data size: \(data.count), Data: \(data.map { String(format: "%02X", $0) }.prefix(20).joined(separator: " "))...")
        } else {
        }
    }
    
    private func clearFrameBuffer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.frameBuffer.isEmpty && self.frameBuffer.count == self.expectedFrameSize { 
                self.frameBuffer = Array(repeating: 0, count: self.expectedFrameSize)
            }
        }
    }
    
    private func clearSevenSegmentData() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.sevenSegmentDigits = [0, 0, 0, 0]
            self.sevenSegmentDots = 0
        }
    }
}
