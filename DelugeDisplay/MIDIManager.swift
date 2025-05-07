import Foundation
import CoreMIDI
import SwiftUI
import OSLog

@MainActor
class MIDIManager: ObservableObject {
    @Published var isConnected = false // UI
    @Published var frameBuffer: [UInt8] = [] // UI
    @Published var sevenSegmentDigits: [UInt8] = [0, 0, 0, 0] // UI
    @Published var sevenSegmentDots: UInt8 = 0 // UI
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
    @Published var isWaitingForConnection = false // UI
    @Published var availablePorts: [MIDIPort] = [] // UI
    @Published var selectedPort: MIDIPort? {
        didSet {
            let newPortName = selectedPort?.name ?? "nil"
            let oldPortName = oldValue?.name ?? "nil"
            logger.debug("selectedPort.didSet: old = \(oldPortName, privacy: .public) (\(String(describing: oldValue?.id), privacy: .public)), new = \(newPortName, privacy: .public) (\(String(describing: self.selectedPort?.id), privacy: .public))")

            if let newId = selectedPort?.id, let oldId = oldValue?.id, newId == oldId {
                logger.debug("selectedPort.didSet: New port ID \(newId) is same as old port ID. No substantive change. Returning.")
                if self.lastSelectedPortName != selectedPort?.name {
                    self.lastSelectedPortName = selectedPort?.name
                }
                return
            }
            
            if selectedPort == nil && oldValue == nil {
                logger.debug("selectedPort.didSet: Both new and old ports are nil. No change. Returning.")
                return
            }

            logger.info("selectedPort changed from \(oldPortName) to \(newPortName). Proceeding with connect/disconnect logic.")

            if self.isConnected {
                disconnect()
            }
            clearFrameBuffer()
            clearSevenSegmentData()

            if let port = selectedPort {
                self.lastSelectedPortName = port.name
                connectToDeluge(portName: port.name)
            } else {
                self.lastSelectedPortName = nil
                updateTimer?.invalidate()
                connectionTimer?.invalidate()
                logger.info("Port deselected. Timers invalidated.")
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
            guard oldValue != self.displayMode else {
                logger.debug("displayMode.didSet: oldValue (\(oldValue.rawValue)) == newDisplayMode (\(self.displayMode.rawValue)). No change in mode value. isSettingInitialMode=\(self.isSettingInitialMode)")
                return
            }

            updateTimer?.invalidate()
            logger.debug("Update timer invalidated due to mode switch from \(oldValue.rawValue) to \(self.displayMode.rawValue).")

            // Clear data for the mode we are LEAVING (oldValue)
            if oldValue == .oled {
                clearFrameBuffer()
                logger.debug("Cleared frame buffer as we are leaving OLED mode.")
            } else if oldValue == .sevenSegment {
                clearSevenSegmentData()
                logger.debug("Cleared 7-segment data as we are leaving 7-Segment mode.")
            }
            
            // Additionally, ensure the new mode's buffer is also pristine.
            // This handles cases where the new mode's buffer might have become stale for other reasons,
            // or if it's the very first switch from an uninitialized state (though init should handle that).
            // This is a "belt and suspenders" approach.
            switch self.displayMode {
            case .oled:
                // If frameBuffer is not already empty (e.g. if we didn't come from OLED, or just to be sure)
                // A simple clearFrameBuffer() here is fine.
                clearFrameBuffer()
                logger.debug("Ensured frame buffer is clear for newly active OLED mode.")
            case .sevenSegment:
                // Similarly, ensure 7-segment data is clear.
                clearSevenSegmentData()
                logger.debug("Ensured 7-segment data is clear for newly active 7-Segment mode.")
            }


            if !isSettingInitialMode { // User-initiated change
                logger.info("Display mode changed by user from \(oldValue.rawValue) to \(self.displayMode.rawValue). Sending toggle and requesting new data.")
                sendDisplayToggleCommand()
                UserDefaults.standard.set(self.displayMode.rawValue, forKey: "displayMode")
                requestDisplayData()
                startUpdateTimer()
            } else { // Programmatic change during initial setup
                logger.info("Initial display mode programmatically set from \(oldValue.rawValue) to \(self.displayMode.rawValue) during initial setup. Not sending toggle.")
                UserDefaults.standard.set(self.displayMode.rawValue, forKey: "displayMode")
                // requestDisplayData() and startUpdateTimer() are handled by the calling context (e.g., setInitialDisplayMode)
            }
        }
    }
    private var isSettingInitialMode: Bool = false
    private var initialProbeCompletedOrModeSet: Bool = false
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
    private var lastSelectedPortName: String? {
        didSet {
            if let name = lastSelectedPortName {
                UserDefaults.standard.set(name, forKey: "lastSelectedPort")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastSelectedPort")
            }
        }
    }
    private var probeTimer: Timer?
    private var hasAttemptedSevenSegmentProbe: Bool = false

    struct MIDIPort: Identifiable {
        let id: MIDIEndpointRef
        let name: String
    }
    
    init() {
        self.isSettingInitialMode = false
        self.initialProbeCompletedOrModeSet = false

        self.smoothingEnabled = UserDefaults.standard.bool(forKey: "smoothingEnabled")

        let initialSmoothingQuality: Image.Interpolation
        if UserDefaults.standard.object(forKey: "smoothingQuality") == nil {
            initialSmoothingQuality = .low
        } else {
            let interpolationValue = UserDefaults.standard.integer(forKey: "smoothingQuality")
            switch interpolationValue {
            case 0: initialSmoothingQuality = .none
            case 1: initialSmoothingQuality = .low
            case 2: initialSmoothingQuality = .medium
            case 3: initialSmoothingQuality = .high
            default: initialSmoothingQuality = .medium
            }
        }
        self.smoothingQuality = initialSmoothingQuality


        if let savedMode = UserDefaults.standard.string(forKey: "displayColorMode"),
           let mode = DelugeDisplayColorMode(rawValue: savedMode) {
            self.displayColorMode = mode
        } else {
            self.displayColorMode = .normal
        }
        
        self.lastSelectedPortName = UserDefaults.standard.string(forKey: "lastSelectedPort")
        
        let savedDisplayModeString = UserDefaults.standard.string(forKey: "displayMode")
        let initialDisplayModeValue: DelugeDisplayMode
        if let savedDisplayMode = savedDisplayModeString,
           let mode = DelugeDisplayMode(rawValue: savedDisplayMode) {
            initialDisplayModeValue = mode
            logger.info("Loaded initial display mode from UserDefaults: \(mode.rawValue)")
        } else {
            initialDisplayModeValue = .oled
            logger.info("Defaulting initial display mode to OLED (no saved preference).")
        }
        _displayMode = Published(initialValue: initialDisplayModeValue)
        
        if UserDefaults.standard.object(forKey: "smoothingQuality") == nil {
            let value: Int
            switch self.smoothingQuality {
                case .none: value = 0
                case .low: value = 1
                case .medium: value = 2
                case .high: value = 3
                @unknown default: value = 1
            }
            UserDefaults.standard.set(value, forKey: "smoothingQuality")
        }
        
        setupMIDI()
    }
    
    deinit {
        logger.info("MIDIManager deinit: Cleanup should ideally have happened via explicit disconnect().")
    }
    
    func setupMIDI() {
        var status = MIDIClientCreateWithBlock("DelugeDisplay" as CFString, &client) { [weak self] notificationPtr in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let now = Date()
                if now.timeIntervalSince(self.lastScanTime) >= self.minimumScanInterval {
                    self.logger.info("MIDI system changed - rescanning ports. Notification: \(notificationPtr.pointee.messageID.rawValue)")
                    await self.scanAvailablePorts()
                    self.lastScanTime = now
                    
                    if let selectedPortName = self.lastSelectedPortName, self.delugeInput == nil || self.delugeOutput == nil {
                        if self.availablePorts.contains(where: { $0.name == selectedPortName }) {
                            self.logger.info("Previously selected port \(selectedPortName) might be available again. Attempting to reconnect.")
                            if let portToSelect = self.availablePorts.first(where: { $0.name == selectedPortName }) {
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
        var localPorts: [MIDIPort] = []
        var portToAutoSelect: MIDIPort? = nil
        var portToReSelect: MIDIPort? = nil
        
        logger.debug("Scanning for available MIDI ports (now on MainActor)...")
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            if let n = name?.takeUnretainedValue() as String? {
                let currentPort = MIDIPort(id: endpoint, name: n)
                localPorts.append(currentPort)
                if !self.delugePortName.isEmpty && n.contains(self.delugePortName) && self.selectedPort == nil && self.lastSelectedPortName == nil && portToAutoSelect == nil {
                    portToAutoSelect = currentPort
                }
                if let lastPortName = self.lastSelectedPortName, n == lastPortName {
                    portToReSelect = currentPort
                }
            }
        }
            
        let oldAvailablePorts = self.availablePorts.map { $0.name }.sorted()
        let newAvailablePorts = localPorts.map { $0.name }.sorted()
        if oldAvailablePorts != newAvailablePorts {
            self.availablePorts = localPorts
            self.logger.info("Available MIDI ports updated: \(localPorts.map { $0.name })")
        }
        
        var finalPortToSelect: MIDIPort? = nil
        if self.selectedPort == nil {
            if let autoPort = portToAutoSelect { finalPortToSelect = autoPort; self.logger.info("Auto-selecting port: \(autoPort.name)") }
            else if let rePort = portToReSelect { finalPortToSelect = rePort; self.logger.info("Re-selecting last used port: \(rePort.name)") }
        }

        if let port = finalPortToSelect {
            if self.selectedPort?.id != port.id { self.selectedPort = port }
        }
        
        if self.selectedPort == nil && self.lastSelectedPortName != nil {
            if !localPorts.contains(where: { $0.name == self.lastSelectedPortName }) {
                self.logger.warning("Last selected port '\(self.lastSelectedPortName!)' is no longer available.")
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
        
        self.isSettingInitialMode = false
        self.initialProbeCompletedOrModeSet = false
        self.hasAttemptedSevenSegmentProbe = false

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
                logger.info("Successfully connected MIDI source for port: \(portName). Starting display mode probe.")
                updateTimer?.invalidate()
                startDisplayModeProbe()
            } else {
                logger.error("Failed to connect MIDI source for port \(portName). Error: \(status)")
                delugeInput = nil
                delugeOutput = nil
            }
        } else {
            logger.error("Could not find both input and output endpoints for port: \(portName)")
        }
    }

    private func startDisplayModeProbe() {
        probeTimer?.invalidate()
        
        isSettingInitialMode = true
        hasAttemptedSevenSegmentProbe = false
        initialProbeCompletedOrModeSet = false

        logger.info("Probing: Requesting OLED data first.")
        sendSysEx(sysExRequestOLED)

        probeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard self.isSettingInitialMode, !self.initialProbeCompletedOrModeSet, !self.hasAttemptedSevenSegmentProbe else {
                self.logger.debug("Probe timer (OLED) fired, but probing already completed or mode set. isSettingInitialMode: \(self.isSettingInitialMode), initialProbeCompletedOrModeSet: \(self.initialProbeCompletedOrModeSet)")
                return
            }
            self.logger.info("Probing: OLED timeout. Requesting 7-Segment data.")
            self.hasAttemptedSevenSegmentProbe = true
            self.sendSysEx(self.sysExRequestSevenSegment)

            self.probeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                 guard let self = self else { return }
                guard self.isSettingInitialMode, !self.initialProbeCompletedOrModeSet else {
                    self.logger.debug("Probe timer (7-Seg) fired, but probing already completed or mode set. isSettingInitialMode: \(self.isSettingInitialMode), initialProbeCompletedOrModeSet: \(self.initialProbeCompletedOrModeSet)")
                    return
                }
                self.logger.info("Probing: 7-Segment timeout. Defaulting mode and completing probe.")
                self.setInitialDisplayMode(self.displayMode)
            }
        }
    }

    private func setInitialDisplayMode(_ mode: DelugeDisplayMode) {
        guard !initialProbeCompletedOrModeSet else {
            logger.debug("setInitialDisplayMode: Probe already completed or mode set. Ignoring for \(mode.rawValue). Current: \(self.displayMode.rawValue)")
            return
        }

        probeTimer?.invalidate()
        
        self.isSettingInitialMode = true
        
        if self.displayMode != mode {
            self.displayMode = mode
        } else {
            logger.debug("setInitialDisplayMode: Target mode \(mode.rawValue) is already the current mode. Ensuring setup finalizes.")
        }
        
        self.isSettingInitialMode = false
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard !self.initialProbeCompletedOrModeSet else {
                self.logger.debug("setInitialDisplayMode async: Probe already completed or mode set while async task was pending. Exiting for \(mode.rawValue).")
                return
            }
            
            self.logger.info("Initial display mode definitively set to: \(mode.rawValue) by setInitialDisplayMode.")
            self.initialProbeCompletedOrModeSet = true
            
            self.startUpdateTimer()
        }
    }

    private func startUpdateTimer() {
        guard !isSettingInitialMode else {
            logger.debug("Deferring start of update timer: isSettingInitialMode is still true (or was true when startUpdateTimer was enqueued).")
            return
        }
        updateTimer?.invalidate()
        logger.debug("Starting regular display update timer for mode: \(self.displayMode.rawValue)")
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
        }
    }
    
    private func clearFrameBuffer() {
        logger.debug("Clearing frame buffer.")
        self.frameBuffer = Array(repeating: 0, count: self.expectedFrameSize)
    }
    
    private func clearSevenSegmentData() {
        logger.debug("Clearing 7-segment data.")
        self.sevenSegmentDigits = [0, 0, 0, 0]
        self.sevenSegmentDots = 0
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
        let portNameToLog = self.lastSelectedPortName ?? "unknown"
        if self.isConnected {
            logger.info("Disconnecting from Deluge on port: \(portNameToLog)")
        } else {
            logger.info("Ensuring MIDI resources are released for port: \(portNameToLog)")
        }
        
        connectionTimer?.invalidate()
        connectionTimer = nil
        updateTimer?.invalidate()
        updateTimer = nil
        probeTimer?.invalidate()
        probeTimer = nil
        
        if let currentInput = self.delugeInput, self.inputPort != 0 {
            MIDIPortDisconnectSource(self.inputPort, currentInput)
            logger.debug("Disconnected source for port \(portNameToLog).")
        }
        
        if self.inputPort != 0 {
            MIDIPortDispose(self.inputPort)
            self.inputPort = 0
            logger.debug("Disposed input port.")
        }
        if self.outputPort != 0 {
            MIDIPortDispose(self.outputPort)
            self.outputPort = 0
            logger.debug("Disposed output port.")
        }
        if self.client != 0 {
            self.client = 0
            logger.debug("Nullified MIDI client reference. Consider proper disposal if needed.")
        }
        
        self.delugeInput = nil
        self.delugeOutput = nil
        
        self.isConnected = false
        self.isWaitingForConnection = false
        clearFrameBuffer()
        clearSevenSegmentData()
        
        self.isSettingInitialMode = false
        self.hasAttemptedSevenSegmentProbe = false
        self.initialProbeCompletedOrModeSet = false
    }

    private func handleMIDIPacketList(_ packetList: MIDIPacketList) {
        var mutablePacketList = packetList
        var p: UnsafeMutablePointer<MIDIPacket> = UnsafeMutableRawPointer(&mutablePacketList.packet).assumingMemoryBound(to: MIDIPacket.self)

        for _ in 0 ..< mutablePacketList.numPackets {
            let packet = p.pointee
            
            let length = Int(packet.length)
            guard length > 0, length <= self.maxSysExSize else {
                Task {
                    await MainActor.run {
                        self.logger.error("Received MIDI packet with invalid length (\(length)). Flushing buffer.")
                        self.sysExBuffer.removeAll()
                        self.isProcessingSysEx = false
                    }
                }
                p = MIDIPacketNext(p)
                continue
            }
            
            let bytes = withUnsafeBytes(of: packet.data) { (rawBufferPointer: UnsafeRawBufferPointer) -> [UInt8] in
                let bufferPointer = rawBufferPointer.bindMemory(to: UInt8.self)
                return Array(bufferPointer.prefix(length))
            }
            
            processQueue.async { [weak self] in
                self?.processSingleMIDIMessageOnBackgroundQueue(bytes)
            }
            
            p = MIDIPacketNext(p)
        }
    }

    private func processSingleMIDIMessageOnBackgroundQueue(_ bytes: [UInt8]) {
        Task { @MainActor [weak self, bytes] in
            guard let self = self else { return }

            for byte in bytes {
                if byte == 0xf0 {
                    self.sysExBuffer.removeAll()
                    self.sysExBuffer.append(byte)
                    self.isProcessingSysEx = true
                } else if byte == 0xf7 && self.isProcessingSysEx {
                    self.sysExBuffer.append(byte)
                    let bufferCopy = self.sysExBuffer
                    self.processSysExMessage(bufferCopy)
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
        guard bytes.count >= 5, bytes[0] == 0xf0, bytes[1] == 0x7d else { return }

        let wasConnectedInitially = self.isConnected
        var dataReceived = false
        
        if bytes.count >= 7 && bytes[2] == 0x02 && bytes[3] == 0x40 && bytes.last == 0xf7 { // OLED
            do {
                let (unpacked, _) = try unpack7to8RLE(Array(bytes[6...(bytes.count - 2)]), maxBytes: self.expectedFrameSize)
                self.frameBuffer = unpacked
                if !self.isConnected { self.isConnected = true }
                dataReceived = true
                if self.isSettingInitialMode && !self.initialProbeCompletedOrModeSet {
                     logger.debug("OLED data received during probe. Setting initial mode to OLED.")
                     setInitialDisplayMode(.oled)
                }
            } catch {
                 logger.error("Error unpacking OLED data: \(error.localizedDescription)")
            }
        } else if bytes.count == 12 && bytes[2] == 0x02 && bytes[3] == 0x41 && bytes.last == 0xf7 { // 7-Seg
            self.sevenSegmentDots = bytes[6]
            self.sevenSegmentDigits = [bytes[7], bytes[8], bytes[9], bytes[10]]
            if !self.isConnected {
                self.isConnected = true
            }
            dataReceived = true
            if self.isSettingInitialMode && !self.initialProbeCompletedOrModeSet {
                logger.debug("7-Segment data received during probe. Setting initial mode to 7-Segment.")
                setInitialDisplayMode(.sevenSegment)
            }
        }
        // Potentially other SysEx message types could be handled here
        
        if dataReceived && !wasConnectedInitially && self.isConnected {
             self.logger.info("Data received. Connected to Deluge on port: \(self.selectedPort?.name ?? self.lastSelectedPortName ?? "unknown")")
             if self.isWaitingForConnection { self.isWaitingForConnection = false }
        }
        // lastPacketTime update was moved to processSingleMIDIMessageOnBackgroundQueue's Task @MainActor block
    }

}
