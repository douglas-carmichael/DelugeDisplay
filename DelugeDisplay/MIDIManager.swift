import Foundation
import CoreMIDI
import SwiftUI
import OSLog

@MainActor
class MIDIManager: ObservableObject {
    @Published var isConnected = false // UI
    @Published var lastFrameBuffer: [UInt8] = [] // UI
    @Published var lastFrameBufferIsSet = false // UI
    @Published var frameBuffer: [UInt8] = [] // UI
    @Published var oledFrameUpdateID: UUID = UUID() // UI
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
            #if DEBUG
            logger.debug("selectedPort.didSet: old = \(oldPortName, privacy: .public) (\(String(describing: oldValue?.id), privacy: .public)), new = \(newPortName, privacy: .public) (\(String(describing: self.selectedPort?.id), privacy: .public))")
            #endif

            if let newId = selectedPort?.id, let oldId = oldValue?.id, newId == oldId {
                #if DEBUG
                logger.debug("selectedPort.didSet: New port ID \(newId) is same as old port ID. No substantive change. Returning.")
                #endif
                if self.lastSelectedPortName != selectedPort?.name {
                    self.lastSelectedPortName = selectedPort?.name
                }
                return
            }
            
            if selectedPort == nil && oldValue == nil {
                #if DEBUG
                logger.debug("selectedPort.didSet: Both new and old ports are nil. No change. Returning.")
                #endif
                return
            }

            #if DEBUG
            logger.info("selectedPort changed from \(oldPortName) to \(newPortName). Proceeding with connect/disconnect logic.")
            #endif

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
                #if DEBUG
                logger.info("Port deselected. Timers invalidated.")
                #endif
            }
        }
    }
    @Published var displayColorMode: DelugeDisplayColorMode {
        didSet {
            UserDefaults.standard.set(displayColorMode.rawValue, forKey: "displayColorMode")
        }
    }
    @Published var oledPixelGridModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(oledPixelGridModeEnabled, forKey: "oledPixelGridModeEnabled")
        }
    }
    @Published var displayMode: DelugeDisplayMode = .oled {
        didSet {
            guard oldValue != self.displayMode else { return }

            let _ = self.displayLogicGeneration &+ 1
            self.displayLogicGeneration = self.displayLogicGeneration &+ 1 
            #if DEBUG
            logger.debug("Display mode changed. New generation: \(self.displayLogicGeneration)")
            #endif

            let previousMode = oldValue
            let currentMode = self.displayMode

            // Original buffer clearing for the mode we are LEAVING
            if previousMode == .sevenSegment {
                clearSevenSegmentData()
                #if DEBUG
                logger.debug("Cleared 7-segment data as we are leaving 7-Segment mode for \(currentMode.rawValue).")
                #endif
            } else if previousMode == .oled {
                // For OLED -> 7SEG, we clear frameBuffer immediately.
                // For 7SEG -> OLED, frameBuffer clearing is handled specially below.
                if currentMode == .sevenSegment { // Only clear if actually going to 7-seg
                    clearFrameBuffer()
                    #if DEBUG
                    logger.debug("Cleared frame buffer as we are leaving OLED mode for \(currentMode.rawValue).")
                    #endif
                }
            }
            
            // Ensure destination 7-segment buffer is clear if switching TO it
            if currentMode == .sevenSegment {
                 clearSevenSegmentData()
                 #if DEBUG
                 logger.debug("Ensured 7-segment data is clear for newly active 7-Segment mode (switched from \(previousMode.rawValue)).")
                 #endif
            }


            if !isSettingInitialMode {
                #if DEBUG
                logger.info("Display mode changed by user from \(previousMode.rawValue) to \(currentMode.rawValue). Processing. Generation: \(self.displayLogicGeneration)")
                #endif
                UserDefaults.standard.set(currentMode.rawValue, forKey: "displayMode")
                
                if previousMode == .sevenSegment && currentMode == .oled {
                    // 1. Clear frame buffer immediately for a clean slate.
                    #if DEBUG
                    logger.info("7SEG->OLED: Clearing frame buffer immediately. Gen: \(self.displayLogicGeneration)")
                    #endif
                    self.clearFrameBuffer() // Ensures DelugeScreenView starts blank.
                    
                    // 2. Tell Deluge to switch its mode
                    #if DEBUG
                    logger.info("7SEG->OLED: Sending toggle command. Gen: \(self.displayLogicGeneration)")
                    #endif
                    sendDisplayToggleCommand()
                    
                    // 3. Delay further actions to allow Deluge to process toggle and send a potential transitional frame (which we might ignore or overwrite)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.075) { // 75ms delay (tune this)
                        // Only proceed if mode and generation haven't changed again
                        if self.displayMode == .oled && self.displayLogicGeneration == self.displayLogicGeneration {
                            // 4. Optional: Re-clear the app's frameBuffer if Deluge sends a transitional frame we don't want.
                            //    If immediate clear + Deluge toggle is clean, this might not be needed.
                            //    For now, let's assume the immediate clear is sufficient and Deluge won't send garbage
                            //    that briefly appears before proper OLED data.
                            //    If issues arise, consider adding a small delay here to ensure the transition frame is skipped.
                            // #if DEBUG
                            // self.logger.info("7SEG->OLED: Delayed: Optionally re-clearing frame buffer. Gen: \(self.displayLogicGeneration)")
                            // #endif
                            // self.clearFrameBuffer()
                            
                            // 5. Request actual OLED data
                            #if DEBUG
                            self.logger.info("7SEG->OLED: Delayed: Requesting OLED data. Gen: \(self.displayLogicGeneration)")
                            #endif
                            self.requestFullOLEDFrame() // Use force display command
                            
                            // 6. Start the update timer *here*, after all transition steps.
                            #if DEBUG
                            self.logger.info("7SEG->OLED: Delayed: Starting update timer. Gen: \(self.displayLogicGeneration)")
                            #endif
                            self.startUpdateTimer(forExplicitMode: .oled, generation: self.displayLogicGeneration)
                        } else {
                            #if DEBUG
                            self.logger.info("7SEG->OLED: Delayed action skipped due to mode/gen change. Expected OLED/Gen\(self.displayLogicGeneration), got \(self.displayMode.rawValue)/Gen\(self.displayLogicGeneration)")
                            #endif
                        }
                    }
                    // startUpdateTimer(forExplicitMode: currentMode, generation: generation)

                } else { // For OLED -> 7SEG, or any other non-problematic transitions
                    if currentMode == .oled && previousMode == .oled { // e.g. port change while in OLED
                        clearFrameBuffer() // Ensure it's clean
                        #if DEBUG
                        logger.debug("OLED->OLED (e.g. port change): Ensuring frame buffer is clear. Gen: \(self.displayLogicGeneration)")
                        #endif
                    }
                    // For OLED->7SEG or other direct transitions, send toggle, request data, and start timer immediately.
                    sendDisplayToggleCommand() // This might be problematic if Deluge expects toggle ONLY for 7SEG->OLED.
                                               // If OLED->7SEG also needs a toggle, it's fine.
                                               // If not, this toggle might flip it back to OLED if it was already 7SEG.
                                               // We established earlier that toggle is needed for *any* switch.
                    if currentMode == .oled {
                        self.requestFullOLEDFrame()
                    } else {
                        self.requestDisplayData(forMode: currentMode)
                    }
                    startUpdateTimer(forExplicitMode: currentMode, generation: self.displayLogicGeneration)
                }
            } else { // isSettingInitialMode == true
                #if DEBUG
                logger.info("Initial display mode programmatically set from \(previousMode.rawValue) to \(currentMode.rawValue). Gen: \(self.displayLogicGeneration)")
                #endif
                UserDefaults.standard.set(currentMode.rawValue, forKey: "displayMode")
                
                // Initial probe logic handles requests and timer.
                // However, if initial mode is set to OLED (e.g. from UserDefaults),
                // and it was previously 7SEG (hypothetically), this special delay logic wouldn't run.
                // This might be fine as initial probe is different.
            }
        }
    }
    private var isSettingInitialMode: Bool = false
    private var initialProbeCompletedOrModeSet: Bool = false

    struct MIDIPort: Identifiable, Hashable /* Equatable is synthesized by Hashable if all members are Equatable, or id can be used */ {
        let id: MIDIEndpointRef // MIDIEndpointRef is UInt32, which is Hashable
        let name: String        // String is Hashable

        // Explicit Equatable conformance (optional if synthesized is sufficient, but good for clarity with Identifiable)
        static func == (lhs: MIDIManager.MIDIPort, rhs: MIDIManager.MIDIPort) -> Bool {
            return lhs.id == rhs.id
        }

        // Hashable conformance can be synthesized by the compiler if all members are Hashable.
        // If explicit hashing is needed:
        // func hash(into hasher: inout Hasher) {
        //     hasher.combine(id)
        // }
    }
    
    private var updateTimer: Timer?
    private var displayLogicGeneration: Int = 0
    private let bomeBoxHeaderSize = 5 // BomeBox injects 5-byte headers
    private let bomeBoxMessageDelay: TimeInterval = 0.02 // Add small delay for BomeBox message coalescence

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
        
        self.oledPixelGridModeEnabled = UserDefaults.standard.bool(forKey: "oledPixelGridModeEnabled")

        self.lastSelectedPortName = UserDefaults.standard.string(forKey: "lastSelectedPort")
        
        let savedDisplayModeString = UserDefaults.standard.string(forKey: "displayMode")
        let initialDisplayModeValue: DelugeDisplayMode
        if let savedDisplayMode = savedDisplayModeString,
           let mode = DelugeDisplayMode(rawValue: savedDisplayMode) {
            initialDisplayModeValue = mode
            #if DEBUG
            logger.info("Loaded initial display mode from UserDefaults: \(mode.rawValue)")
            #endif
        } else {
            initialDisplayModeValue = .oled
            #if DEBUG
            logger.info("Defaulting initial display mode to OLED (no saved preference).")
            #endif
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
        #if DEBUG
        logger.info("MIDIManager deinit: Explicit disconnect() should have been called prior to deinitialization to release MIDI resources.")
        #endif
        // DO NOT call self.disconnect() here due to actor isolation.
        // All necessary cleanup of MIDI resources (ports, client)
        // must be handled by an explicit call to disconnect() from a @MainActor context
        // before this MIDIManager instance is deinitialized.
    }
    
    func disconnect() {
        let portNameToLog = self.lastSelectedPortName ?? "unknown"
        #if DEBUG
        logger.info("MIDIManager.disconnect() called for port: \(portNameToLog). Current connection status: \(self.isConnected)")
        #endif
        
        connectionTimer?.invalidate()
        connectionTimer = nil
        updateTimer?.invalidate()
        updateTimer = nil
        // probeTimer?.invalidate()
        
        if let currentInput = self.delugeInput, self.inputPort != 0 {
            _ = MIDIPortDisconnectSource(self.inputPort, currentInput)
            #if DEBUG
            // logger.debug("Disconnected source for port \(portNameToLog).")
            #endif
        }
        self.delugeInput = nil
        
        if self.inputPort != 0 {
            _ = MIDIPortDispose(self.inputPort)
            #if DEBUG
            // logger.debug("Disposed input port.")
            #endif
            self.inputPort = 0
        }
        if self.outputPort != 0 {
            _ = MIDIPortDispose(self.outputPort)
            #if DEBUG
            // logger.debug("Disposed output port.")
            #endif
            self.outputPort = 0
        }
        
        self.delugeOutput = nil
        
        if self.client != 0 {
            _ = MIDIClientDispose(self.client)
            #if DEBUG
            // logger.debug("Disposed MIDI client.")
            #endif
            self.client = 0
        }
        
        if self.isConnected {
            self.isConnected = false
        }
        if self.isWaitingForConnection {
            self.isWaitingForConnection = false
        }
        
        self.isSettingInitialMode = false
        self.initialProbeCompletedOrModeSet = false
        #if DEBUG
        logger.info("MIDIManager.disconnect() finished.")
        #endif
    }

    func setupMIDI() {
        var status = MIDIClientCreateWithBlock("DelugeDisplay" as CFString, &client) { [weak self] notificationPtr in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let now = Date()
                if now.timeIntervalSince(self.lastScanTime) >= self.minimumPortScanInterval {
                    #if DEBUG
                    self.logger.info("MIDI system changed - rescanning ports. Notification: \(notificationPtr.pointee.messageID.rawValue)")
                    #endif
                    self.scanAvailablePorts()
                    self.lastScanTime = now
                    
                    if let selectedPortName = self.lastSelectedPortName, self.delugeInput == nil || self.delugeOutput == nil {
                        if self.availablePorts.contains(where: { $0.name == selectedPortName }) {
                            #if DEBUG
                            self.logger.info("Previously selected port \(selectedPortName) might be available again. Attempting to reconnect.")
                            #endif
                            if let portToSelect = self.availablePorts.first(where: { $0.name == selectedPortName }) {
                                self.selectedPort = portToSelect
                            }
                        }
                    }
                }
            }
        }
        guard status == noErr else {
            #if DEBUG
            logger.error("Failed to create MIDI client: \(status)")
            #endif
            return
        }
        
        status = MIDIInputPortCreateWithBlock(client, "Input" as CFString, &inputPort) { [weak self] packetListPointer, _ in
            guard let strongSelf = self else {
                return
            }
            var packets: [[UInt8]] = []

            var currentPacket: UnsafePointer<MIDIPacket> = UnsafeRawPointer(packetListPointer).advanced(by: MemoryLayout<UInt32>.size).assumingMemoryBound(to: MIDIPacket.self)

            for _ in 0..<packetListPointer.pointee.numPackets {
                let packetStruct = currentPacket.pointee
                let length = Int(packetStruct.length)

                if length > 0 && length <= strongSelf.maxSysExSize {
                    let packetDataBytes: [UInt8] = withUnsafeBytes(of: packetStruct.data) { rawBufferPtr in
                        Array(rawBufferPtr.prefix(length))
                    }
                    #if DEBUG
                    DispatchQueue.main.async { // Log on main actor to use self.logger
                         strongSelf.logger.debug("Raw MIDI Packet Received (\(length) bytes): \(packetDataBytes.map { String(format: "%02X", $0) })")
                    }
                    #endif
                    packets.append(packetDataBytes)
                } else {
                    // Log skip if necessary, but critical logs were removed for build stability
                    #if DEBUG
                    DispatchQueue.main.async { // Log on main actor to use self.logger
                        if length > strongSelf.maxSysExSize {
                            strongSelf.logger.error("Raw MIDI Packet too large (\(length) bytes), skipped. Max packet data size: \(strongSelf.maxSysExSize)")
                        } else if length <= 0 {
                            strongSelf.logger.debug("Raw MIDI Packet empty or invalid length (\(length) bytes), skipped.")
                        }
                    }
                    #endif
                }
                
                // Advance to the next packet. MIDIPacketNext takes and returns UnsafePointer<MIDIPacket>.
                // This addresses the error "Cannot assign value of type 'UnsafeMutablePointer<MIDIPacket>' to type 'UnsafePointer<MIDIPacket>'"
                // by ensuring the RHS is explicitly UnsafePointer<MIDIPacket>.
                currentPacket = UnsafePointer(MIDIPacketNext(currentPacket))
            }
            
            if packets.isEmpty && packetListPointer.pointee.numPackets > 0 {
            }

            for bytes in packets {
                strongSelf.processQueue.async { [weak strongSelfInQueue = strongSelf] in
                    guard let selfForTask = strongSelfInQueue else {
                        return
                    }
                    Task { @MainActor in
                        selfForTask.processSingleMIDIMessageOnBackgroundQueue(bytes)
                    }
                }
            }
        }
        guard status == noErr else {
            #if DEBUG
            logger.error("Failed to create input port: \(status)")
            #endif
            return
        }
        
        status = MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)
        guard status == noErr else {
            #if DEBUG
            logger.error("Failed to create output port: \(status)")
            #endif
            return
        }
        
        scanAvailablePorts()
        startConnectionTimer()
    }
    
    func scanAvailablePorts() {
        #if DEBUG
        self.logger.debug("--- DUMPING ALL MIDI SOURCES (Inputs) ---")
        let numSources = MIDIGetNumberOfSources()
        if numSources == 0 {
            self.logger.debug("No MIDI sources found.")
        } else {
            for i in 0..<numSources {
                let endpoint = MIDIGetSource(i)
                var nameCF: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameCF)
                let name = nameCF?.takeRetainedValue() as String? ?? "(Unnamed Source)"
                self.logger.debug("Source Port \(i): \"\(name)\" (ID: \(endpoint))")
            }
        }
        self.logger.debug("--- END DUMPING MIDI SOURCES ---")

        self.logger.debug("--- DUMPING ALL MIDI DESTINATIONS (Outputs) ---")
        let numDestinations = MIDIGetNumberOfDestinations()
        if numDestinations == 0 {
            self.logger.debug("No MIDI destinations found.")
        } else {
            for i in 0..<numDestinations {
                let endpoint = MIDIGetDestination(i)
                var nameCF: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameCF)
                let name = nameCF?.takeRetainedValue() as String? ?? "(Unnamed Destination)"
                self.logger.debug("Destination Port \(i): \"\(name)\" (ID: \(endpoint))")
            }
        }
        self.logger.debug("--- END DUMPING MIDI DESTINATIONS ---")
        #endif
        
        var localPorts: [MIDIPort] = []
        var portToAutoSelect: MIDIPort? = nil
        var portToReSelect: MIDIPort? = nil
        
        #if DEBUG
        logger.debug("Scanning for available MIDI ports to populate UI list (now on MainActor)...")
        #endif
        
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            var nameCF: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameCF)
            if let n = nameCF?.takeUnretainedValue() as String? {
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
            #if DEBUG
            self.logger.info("Available MIDI ports updated: \(localPorts.map { $0.name })")
            #endif
        }
        
        var finalPortToSelect: MIDIPort? = nil
        if self.selectedPort == nil {
            if let autoPort = portToAutoSelect { finalPortToSelect = autoPort;
                #if DEBUG
                self.logger.info("Auto-selecting port: \(autoPort.name)")
                #endif
            }
            else if let rePort = portToReSelect { finalPortToSelect = rePort;
                #if DEBUG
                self.logger.info("Re-selecting last used port: \(rePort.name)")
                #endif
            }
        }

        if let port = finalPortToSelect {
            if self.selectedPort?.id != port.id { self.selectedPort = port }
        }
        
        if self.selectedPort == nil && self.lastSelectedPortName != nil {
            if !localPorts.contains(where: { $0.name == self.lastSelectedPortName }) {
                #if DEBUG
                self.logger.warning("Last selected port '\(self.lastSelectedPortName!)' is no longer available.")
                #endif
            }
        }
    }
    
    private func connectToDeluge(portName: String) {
        #if DEBUG
        logger.info("Attempting to connect to Deluge on port: \(portName)")
        #endif
        
        guard client != 0, inputPort != 0, outputPort != 0 else {
            #if DEBUG
            logger.warning("MIDI client/ports not initialized. Attempting to re-setup MIDI.")
            #endif
            setupMIDI()
            return
        }
        
        if let currentInput = delugeInput {
            #if DEBUG
            logger.debug("Disconnecting from previous input source.")
            #endif
            MIDIPortDisconnectSource(inputPort, currentInput)
        }
        
        delugeInput = nil
        delugeOutput = nil
        
        self.isSettingInitialMode = false
        self.initialProbeCompletedOrModeSet = false
        
        self.isConnected = false
        self.isWaitingForConnection = true

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
                #if DEBUG
                logger.debug("Found matching output endpoint: \(n) (ID: \(endpoint))")
                #endif
                break
            }
        }
        
        for i in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(i)
            var nameCF: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameCF)
            if let n = nameCF?.takeUnretainedValue() as String?, n == portName {
                foundInput = endpoint
                #if DEBUG
                logger.debug("Found matching input endpoint: \(n) (ID: \(endpoint))")
                #endif
                break
            }
        }
        
        if let input = foundInput, let output = foundOutput {
            delugeInput = input
            delugeOutput = output
            
            let status = MIDIPortConnectSource(inputPort, input, nil)
            if status == noErr {
                #if DEBUG
                logger.info("Successfully connected MIDI source for port: \(portName). Setting initial display mode.")
                #endif
                updateTimer?.invalidate() // Stop any old timers
                setInitialDisplayMode(self.displayMode) // Assert the current mode
            } else {
                #if DEBUG
                logger.error("Failed to connect MIDI source for port \(portName). Error: \(status)")
                #endif
                delugeInput = nil
                delugeOutput = nil
            }
        } else {
            #if DEBUG
            logger.error("Could not find both input and output endpoints for port: \(portName)")
            #endif
        }
    }

    private func setInitialDisplayMode(_ mode: DelugeDisplayMode) {
        guard !initialProbeCompletedOrModeSet else {
            #if DEBUG
            logger.debug("setInitialDisplayMode: Initial setup already completed or mode set. Ignoring for \(mode.rawValue). Current: \(self.displayMode.rawValue), initialProbeCompletedOrModeSet: \(self.initialProbeCompletedOrModeSet)")
            #endif
            return
        }

        let previousIsSettingInitialMode = self.isSettingInitialMode
        self.isSettingInitialMode = true

        if self.displayMode != mode {
            self.displayLogicGeneration &+= 1
            #if DEBUG
            logger.debug("setInitialDisplayMode: Setting displayMode from \(self.displayMode.rawValue) to \(mode.rawValue) for initial setup. New generation: \(self.displayLogicGeneration)")
            #endif
            self.displayMode = mode
        } else {
            #if DEBUG
            logger.debug("setInitialDisplayMode: Target mode \(mode.rawValue) is already the current mode for initial setup. Finalizing. Gen: \(self.displayLogicGeneration)")
            #endif
        }
        
        #if DEBUG
        logger.info("setInitialDisplayMode [Gen \(self.displayLogicGeneration)]: Finalizing initial setup for mode \(mode.rawValue).")
        #endif
        
        let capturedGeneration = self.displayLogicGeneration
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.050) { [weak self] in // Minimal delay for first request
            guard let self = self else { return }

            guard self.displayMode == mode,
                  self.displayLogicGeneration == capturedGeneration,
                  !self.initialProbeCompletedOrModeSet else {
                #if DEBUG
                self.logger.info("setInitialDisplayMode (delayed, path 1 for req1) [Expected Gen \(capturedGeneration) for \(mode.rawValue)]: Action skipped. State changed or setup already completed. Current: \(self.displayMode.rawValue)/Gen\(self.displayLogicGeneration)/Completed:\(self.initialProbeCompletedOrModeSet)")
                #endif
                if !previousIsSettingInitialMode { self.isSettingInitialMode = false }
                return
            }

            #if DEBUG
            self.logger.info("setInitialDisplayMode (delayed, req1) [Gen \(capturedGeneration)]: Requesting data for initial mode \(mode.rawValue).")
            #endif
            if mode == .oled {
                self.requestFullOLEDFrame()
            } else {
                self.requestDisplayData(forMode: mode)
            }

            // Schedule second request and finalization
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.100) { [weak self] in // Further delay for second request + finalization
                guard let self = self else { return }
                guard self.displayMode == mode,
                      self.displayLogicGeneration == capturedGeneration,
                      !self.initialProbeCompletedOrModeSet else {
                        #if DEBUG
                        self.logger.info("setInitialDisplayMode (delayed, path 2 for req2/finalize) [Expected Gen \(capturedGeneration) for \(mode.rawValue)]: Action skipped. State changed or setup already completed.")
                        #endif
                        if !previousIsSettingInitialMode { self.isSettingInitialMode = false } // Ensure flag is reset if we bail early
                        return
                }

                #if DEBUG
                self.logger.info("setInitialDisplayMode (delayed, req2) [Gen \(capturedGeneration)]: Requesting data AGAIN for initial mode \(mode.rawValue).")
                #endif
                if mode == .oled {
                    self.requestFullOLEDFrame()
                } else {
                    self.requestDisplayData(forMode: mode)
                }

                self.isSettingInitialMode = false
                self.initialProbeCompletedOrModeSet = true
                #if DEBUG
                self.logger.info("setInitialDisplayMode (delayed, finalized) [Gen \(capturedGeneration)]: Initial setup complete. Mode: \(mode.rawValue). Starting update timer.")
                #endif
                self.startUpdateTimer(forExplicitMode: mode, generation: capturedGeneration)
            }
        }
    }

    func refreshDisplay() {
        logger.info("Refresh Display command triggered.")
        
        let currentMode = self.displayMode

        // Clear the current display's buffer
        if currentMode == .oled {
            logger.debug("RefreshDisplay: Clearing OLED frame buffer.")
            clearFrameBuffer()
        } else {
            logger.debug("RefreshDisplay: Clearing 7-segment data.")
            clearSevenSegmentData()
        }

        // Request a full update for the current mode
        if currentMode == .oled {
            logger.debug("RefreshDisplay: Requesting full OLED frame.")
            // Send the command to force a full OLED frame.
            // We use requestFullOLEDFrame as it directly sends sysExRequestDisplayForce.
            requestFullOLEDFrame()
        } else { // SevenSegment
            logger.debug("RefreshDisplay: Requesting 7-segment data.")
            // For 7-segment, any request is a "full" request.
            requestDisplayData(forMode: .sevenSegment)
        }
        
        // It might be beneficial to briefly restart the update timer
        // to ensure it's aligned after a manual refresh, especially if
        // the connection was in a weird state.
        // However, the existing timer logic should pick up if data flow resumes.
        // For now, let's rely on the existing timer logic.
        // If issues arise, consider:
        // self.startUpdateTimer(forExplicitMode: currentMode, generation: generation)
        
        // Trigger a UI update for OLED if that's the mode, as clearFrameBuffer already does.
        if currentMode == .oled {
            self.oledFrameUpdateID = UUID()
        }
    }

    private func startUpdateTimer(forExplicitMode modeToUse: DelugeDisplayMode, generation: Int) {
        updateTimer?.invalidate()

        let modeForThisTimer = modeToUse
        let capturedGenerationForTimer = generation

        let interval: TimeInterval = self.minimumScreenDeltaScanInterval
        
        let newTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timerThatFired in
            Task { @MainActor [weak self, weak timerThatFired, capturedGeneration = capturedGenerationForTimer] in
                guard let strongSelf = self, let strongTimerThatFired = timerThatFired else {
                    return
                }

                if strongSelf.displayLogicGeneration == capturedGeneration &&
                   strongSelf.updateTimer === strongTimerThatFired &&
                   strongTimerThatFired.isValid {
                    #if DEBUG
                    strongSelf.logger.debug("Timer task: Requesting data for \(modeForThisTimer.rawValue). Generation: \(capturedGeneration).")
                    #endif
                    strongSelf.requestDisplayDataIfNecessary(forMode: modeForThisTimer)
                } else {
                    #if DEBUG
                    var reason = ""
                    if strongSelf.displayLogicGeneration != capturedGeneration { reason += "GenerationMismatch (Expected:\(capturedGeneration),Got:\(strongSelf.displayLogicGeneration));" }
                    if strongSelf.updateTimer !== strongTimerThatFired { reason += "NotCurrentTimerInstance;" }
                    if !strongTimerThatFired.isValid { reason += "TimerInstanceNotValid;" }
                    strongSelf.logger.notice("Ignored timer callback. Reason: \(reason). Originally for mode: \(modeForThisTimer.rawValue).")
                    #endif
                }
            }
        }
        self.updateTimer = newTimer
    }

    private func requestDisplayDataIfNecessary(forMode mode: DelugeDisplayMode) {
        guard mode == self.displayMode else {
            #if DEBUG
            self.logger.debug("Timer fired for mode \(mode.rawValue), but current mode is \(self.displayMode.rawValue). Skipping data request by timer.")
            #endif
            return
        }

        let currentModeInterval: TimeInterval = self.minimumScreenDeltaScanInterval
    
        let shouldRequest = (self.isConnected || self.isWaitingForConnection) && Date().timeIntervalSince(self.lastPacketTime) > currentModeInterval
        
        if shouldRequest {
            self.requestDisplayDelta()
        }
    }
    
    private func requestDisplayData(forMode mode: DelugeDisplayMode) {
        guard self.isConnected || self.isWaitingForConnection || self.isSettingInitialMode else {
            #if DEBUG
            self.logger.debug("Skipping data request: Not connected, not waiting for connection, and not in initial mode setting.")
            #endif
            return
        }

        let sysExCommand: [UInt8]

        switch mode {
        case .oled:
            #if DEBUG
            self.logger.debug("Requesting OLED display data (for explicitly passed mode).")
            #endif
            sysExCommand = self.sysExRequestOLED
        case .sevenSegment:
            #if DEBUG
            self.logger.debug("Requesting 7-segment display data (for explicitly passed mode).")
            #endif
            sysExCommand = self.sysExRequestSevenSegment
        }
        
        // Modify these constants near the top for better timing handling
        // Add small delay for BomeBox message timing
        DispatchQueue.main.asyncAfter(deadline: .now() + bomeBoxMessageDelay) { [weak self] in
            self?.sendSysEx(sysExCommand)
        }
    }
    
    private func requestDisplayDelta() {
        guard self.isConnected || self.isWaitingForConnection || self.isSettingInitialMode else {
            #if DEBUG
            self.logger.debug("Skipping data request: Not connected, not waiting for connection, and not in initial mode setting.")
            #endif
            return
        }

        let sysExCommand = self.lastFrameBufferIsSet ? self.sysExRequestDisplay: self.sysExRequestDisplayForce
        
        // Add small delay for BomeBox message timing
        DispatchQueue.main.asyncAfter(deadline: .now() + bomeBoxMessageDelay) { [weak self] in
            self?.sendSysEx(sysExCommand)
        }
    }
    
    private func requestFullOLEDFrame() {
        guard self.isConnected || self.isWaitingForConnection || self.isSettingInitialMode else {
            #if DEBUG
            self.logger.debug("Skipping full OLED frame request: Not connected, not waiting for connection, and not in initial mode setting.")
            #endif
            return
        }
        #if DEBUG
        self.logger.debug("Requesting FULL OLED display data (explicitly, using force command).")
        #endif
        self.sendSysEx(self.sysExRequestDisplayForce)
    }
    
    private func sendDisplayToggleCommand() {
        let command = self.sysExToggleDisplayScreen
        
        #if DEBUG
        self.logger.info("Sending display toggle command to Deluge.")
        #endif
        
        // Add small delay for BomeBox message timing
        DispatchQueue.main.asyncAfter(deadline: .now() + bomeBoxMessageDelay) { [weak self] in
            self?.sendSysEx(command)
        }
    }
    
    private func sendSysEx(_ data: [UInt8]) {
        guard let output = delugeOutput else {
            #if DEBUG
            logger.warning("sendSysEx: Deluge output endpoint is nil. Cannot send.")
            #endif
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
        
        #if DEBUG
        let commandType = (data == sysExRequestOLED) ? "OLED Req" : (data == sysExRequestSevenSegment) ? "7Seg Req" : (data == sysExToggleDisplayScreen) ? "Toggle Req" : "Other SysEx"
        logger.debug("sendSysEx: Attempting to send \(commandType): \(data.map { String(format: "%02X", $0) })")
        #endif

        let sendStatus: OSStatus = MIDISend(outputPort, output, &packetList)
        
        if sendStatus != noErr {
            #if DEBUG
            logger.error("Failed to send SysEx data. MIDISend returned error code: \(sendStatus). Data size: \(data.count), Data: \(data.map { String(format: "%02X", $0) }.prefix(20).joined(separator: " "))...")
            #endif
        }
    }
    
    private func clearFrameBuffer() {
        #if DEBUG
        logger.debug("Clearing frame buffer.")
        #endif
        self.frameBuffer = Array(repeating: 0, count: self.expectedFrameSize)
        self.oledFrameUpdateID = UUID()
        // Then clear last frame buffer
        self.lastFrameBuffer = Array(repeating: 0, count: self.expectedFrameSize)
        self.lastFrameBufferIsSet = false
    }
    
    private func clearSevenSegmentData() {
        #if DEBUG
        logger.debug("Clearing 7-segment data.")
        #endif
        self.sevenSegmentDigits = [0, 0, 0, 0]
        self.sevenSegmentDots = 0
    }
    
    private func startConnectionTimer() {
        connectionTimer?.invalidate()
        guard lastSelectedPortName != nil || selectedPort != nil else {
            #if DEBUG
            logger.info("No port selected or previously selected. Connection timer not started.")
            #endif
            return
        }
        
        #if DEBUG
        logger.debug("Starting connection timer.")
        #endif
        isWaitingForConnection = true
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
            
                if self.isConnected {
                    if self.isWaitingForConnection {
                        #if DEBUG
                        self.logger.info("Connection established. Stopping explicit connection attempts by timer.")
                        #endif
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
            
                #if DEBUG
                self.logger.info("Connection timer fired. Attempting to connect/reconnect to: \(portNameToConnect)")
                #endif
            
                if self.delugeInput == nil || self.delugeOutput == nil {
                    #if DEBUG
                    self.logger.debug("Connection timer: Endpoints not set for \(portNameToConnect). Calling connectToDeluge.")
                    #endif
                    self.connectToDeluge(portName: portNameToConnect)
                } else {
                    #if DEBUG
                    self.logger.debug("Connection timer: Endpoints set for \(portNameToConnect), but not connected. Requesting display data for current mode: \(self.displayMode.rawValue).")
                    #endif
                    self.requestDisplayData(forMode: self.displayMode)
                }
            }
        }
    }

    private func processSingleMIDIMessageOnBackgroundQueue(_ bytes: [UInt8]) {
        Task { @MainActor [weak self, bytes] in
            guard let self = self else { return }

            var processedBytes = bytes
            
            if bytes.count > self.bomeBoxHeaderSize {
                if let firstF0Index = bytes.firstIndex(of: 0xF0) {
                    if firstF0Index > 0 && firstF0Index <= self.bomeBoxHeaderSize {
                        processedBytes = Array(bytes[firstF0Index...])
                    }
                }
            }

            for byte in processedBytes {
                if self.bomeBoxHeaderSkipCountdown > 0 {
                    self.bomeBoxHeaderSkipCountdown -= 1
                    continue
                }

                if byte == 0xf0 {
                    if self.isProcessingSysEx && !self.sysExBuffer.isEmpty {
                        if self.sysExBuffer.prefix(2) == [0xF0, 0x7D] {
                            // This is a valid Deluge message that got interrupted
                            #if DEBUG
                            self.logger.warning("BomeBox F0 Interruption: Current SysEx buffer (isDeluge=\(self.sysExBuffer.prefix(2) == [0xF0, 0x7D])) has \(self.sysExBuffer.count) bytes. First few: \(self.sysExBuffer.prefix(10).map { String(format: "%02X", $0) }). Attempting to process this potentially incomplete message.")
                            #endif
                            let bufferCopy = self.sysExBuffer
                            self.processSysExMessage(bufferCopy)
                        }
                        self.sysExBuffer.removeAll()
                    }
                    self.sysExBuffer = [byte]
                    self.isProcessingSysEx = true
                    self.bomeBoxHeaderSkipCountdown = 0
                    
                } else if byte == 0xf7 && self.isProcessingSysEx {
                    self.sysExBuffer.append(byte)
                    let bufferCopy = self.sysExBuffer
                    #if DEBUG
                    self.logger.debug("Processing assembled SysEx message (\(bufferCopy.count) bytes)")
                    #endif
                    self.processSysExMessage(bufferCopy)
                    self.sysExBuffer.removeAll()
                    self.isProcessingSysEx = false
                    self.bomeBoxHeaderSkipCountdown = 0
                    
                } else if self.isProcessingSysEx {
                    if self.sysExBuffer.count < self.maxSysExSize {
                        self.sysExBuffer.append(byte)
                    } else {
                        self.logger.error("SysEx buffer overflow. Max size: \(self.maxSysExSize). Discarding message.")
                        self.sysExBuffer.removeAll()
                        self.isProcessingSysEx = false
                        self.bomeBoxHeaderSkipCountdown = 0
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
        var dataReceivedThisMessage = false
        var oledDataEstablishedConnectionThisMessage = false
        
        // Detect frame type
        let isFullOLEDFrame = bytes.count >= 7 &&
                             bytes[2] == 0x02 &&
                             bytes[3] == 0x40 &&
                             (bytes[4] == 0x01 || // Standard full frame
                              (bytes[4] == 0x02 && bytes[5] == 0x00)) // BomeBox chunked full frame
        
        if isFullOLEDFrame { // Full OLED frame
            do {
                let dataStartIndex = (bytes[4] == 0x01) ? 6 : 7 // Adjust start index based on header type
                #if DEBUG
                self.logger.debug("FULL FRAME: Raw OLED SysEx. MIDI Packet Payload size (for RLE decoding): \(bytes[dataStartIndex...(bytes.count - 2)].count) bytes.")
                #endif
                let (unpacked, _) = try unpack7to8RLE(Array(bytes[dataStartIndex...(bytes.count - 2)]), maxBytes: self.expectedFrameSize)
                #if DEBUG
                let packetDesc = bytes.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " ")
                self.logger.debug("FULL FRAME: Unpacked size: \(unpacked.count). Expected: \(self.expectedFrameSize). Packet starts: \(packetDesc)")
                #endif

                if unpacked.count < self.expectedFrameSize {
                    self.logger.error("Corrupted Full OLED Frame: Unpacked size (\(unpacked.count)) is less than expected (\(self.expectedFrameSize)). Discarding frame. Packet starts: \(bytes.prefix(10).map { String(format: "%02X", $0) })")
                    return // Exit processing for this message
                }
                
                var finalFrameData = unpacked
                if unpacked.count > self.expectedFrameSize {
                    self.logger.warning("Received full OLED data size (\(unpacked.count)) is greater than expected (\(self.expectedFrameSize)). Truncating.")
                    finalFrameData = Array(unpacked.prefix(self.expectedFrameSize))
                }

                self.lastFrameBuffer = finalFrameData
                self.lastFrameBufferIsSet = true
                self.frameBuffer = finalFrameData
                self.oledFrameUpdateID = UUID()
                
                if !self.isConnected { self.isConnected = true }
                dataReceivedThisMessage = true
                if !wasConnectedInitially && self.isConnected {
                    oledDataEstablishedConnectionThisMessage = true
                }
                
                if self.isSettingInitialMode && !self.initialProbeCompletedOrModeSet {
                    #if DEBUG
                    self.logger.info("processSysExMessage: Full OLED data received during initial mode setting. Finalizing with OLED mode.")
                    #endif
                    self.setInitialDisplayMode(.oled)
                }
            } catch {
                self.logger.error("Error unpacking OLED full frame data: \(error.localizedDescription)")
            }
        } else if bytes.count >= 7 && bytes[2] == 0x02 && bytes[3] == 0x40 && bytes[4] == 0x02 { // Delta OLED
            do {
                #if DEBUG
                self.logger.debug("DELTA FRAME: Raw OLED SysEx. MIDI Packet Payload size (for RLE decoding): \(bytes[7...(bytes.count - 2)].count) bytes.")
                #endif
                let (unpacked, _) = try unpack7to8RLE(Array(bytes[7...(bytes.count - 2)]), maxBytes: self.expectedFrameSize)
                #if DEBUG
                let packetDesc = bytes.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " ")
                self.logger.debug("DELTA FRAME: First byte changed: \(Int(bytes[5]) * 8). Unpacked size: \(unpacked.count). Packet starts: \(packetDesc)")
                #endif

                let firstByteChanged: Int = Int(bytes[5]) * 8

                // Ensure framebuffer is initialized if we haven't received a full frame yet
                var bufferWasInitializedByThisDelta = false
                if !self.lastFrameBufferIsSet {
                    self.frameBuffer = Array(repeating: 0, count: self.expectedFrameSize)
                    bufferWasInitializedByThisDelta = true
                    #if DEBUG
                    self.logger.warning("Processing delta OLED frame but no full frame has been set. Initializing framebuffer to zeros.")
                    #endif
                }

                // Handle chunked frames from BomeBox
                if firstByteChanged + unpacked.count <= self.expectedFrameSize {
                    // Update the frame buffer only if we're within bounds
                    self.frameBuffer.replaceSubrange(firstByteChanged..<(firstByteChanged + unpacked.count), with: unpacked)
                    self.lastFrameBuffer = self.frameBuffer // Always update last buffer after successful delta
                    if bufferWasInitializedByThisDelta {
                        self.lastFrameBufferIsSet = true
                        #if DEBUG
                        self.logger.info("Delta processing: lastFrameBufferIsSet is now true after initializing and applying the first delta.")
                        #endif
                    }
                    self.oledFrameUpdateID = UUID()
                    
                    if !self.isConnected { self.isConnected = true }
                    dataReceivedThisMessage = true
                    if !wasConnectedInitially && self.isConnected {
                        oledDataEstablishedConnectionThisMessage = true
                    }

                    if self.isSettingInitialMode && !self.initialProbeCompletedOrModeSet {
                        #if DEBUG
                        self.logger.info("processSysExMessage: Delta OLED data received during initial mode setting. Finalizing with OLED mode.")
                        #endif
                        self.setInitialDisplayMode(.oled)
                    }
                } else {
                    #if DEBUG
                    self.logger.error("Delta offset (\(firstByteChanged)) + size (\(unpacked.count)) exceeds frameBuffer size (\(self.expectedFrameSize))")
                    #endif
                }
            } catch {
                self.logger.error("Error unpacking OLED delta frame data: \(error.localizedDescription)")
            }
        }

        // Rest of function remains unchanged
        if bytes.count == 12 && bytes[2] == 0x02 && bytes[3] == 0x41 && bytes.last == 0xf7 {
            self.sevenSegmentDots = bytes[6]
            self.sevenSegmentDigits = [bytes[7], bytes[8], bytes[9], bytes[10]]
            if !self.isConnected {
                self.isConnected = true
            }
            dataReceivedThisMessage = true
            // No oledDataEstablishedConnectionThisMessage for 7-segment
            if self.isSettingInitialMode && !self.initialProbeCompletedOrModeSet {
                #if DEBUG
                self.logger.info("processSysExMessage: 7-segment data received during initial mode setting. Finalizing with 7-segment mode.")
                #endif
                self.setInitialDisplayMode(.sevenSegment)
            }
        }
        
        if dataReceivedThisMessage && !wasConnectedInitially && self.isConnected {
             self.logger.info("Data received. Connected to Deluge on port: \(self.selectedPort?.name ?? self.lastSelectedPortName ?? "unknown")")
             if self.isWaitingForConnection { self.isWaitingForConnection = false }

            // Diagnostic - force another oledFrameUpdateID change slightly after becoming connected
            // This now applies if *any* OLED data (full or delta) established the connection.
            if oledDataEstablishedConnectionThisMessage {
                #if DEBUG
                self.logger.info("DIAGNOSTIC: First OLED data (full or delta) just processed and established connection, forcing another UI update trigger for Canvas.")
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in // 50ms delay
                    guard let self = self else { return }
                    self.oledFrameUpdateID = UUID()
                }
            }
        }
    }

    private let processQueue = DispatchQueue(label: "com.delugedisplay.process", qos: .userInteractive)
    private let frameUpdateQueue = DispatchQueue(label: "com.delugedisplay.frame", qos: .userInteractive)
    private let expectedFrameSize = 768
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
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0
    private var delugeInput: MIDIEndpointRef?
    private var delugeOutput: MIDIEndpointRef?
    private var sysExBuffer: [UInt8] = []
    private var connectionTimer: Timer?
    private var lastPacketTime = Date()
    private var isProcessingSysEx = false
    private var lastScanTime: Date = Date()
    private let minimumScreenDeltaScanInterval: TimeInterval = 0.1 // Increase from 0.05 to give BomeBox more headroom
    private let minimumPortScanInterval: TimeInterval = 5.0
    private let sysExRequestOLED: [UInt8] = [0xf0, 0x7d, 0x02, 0x00, 0x01, 0xf7]
    private let sysExRequestDisplay: [UInt8] = [0xf0, 0x7d, 0x02, 0x00, 0x02, 0xf7]
    private let sysExRequestDisplayForce: [UInt8] = [0xf0, 0x7d, 0x02, 0x00, 0x03, 0xf7]
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
    private var bomeBoxHeaderSkipCountdown = 0
}
