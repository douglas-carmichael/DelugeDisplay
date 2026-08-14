//
//  StressTester.swift
//  DelugeDisplay
//
//  Host side of the firmware's display MIDI link stress exerciser (display SysEx
//  command family 0x03; see docs/deluge-firmware-spec-display-midi-exerciser.md).
//  Drives start/stop/stats over the existing legacy-framed transport, verifies the
//  per-frame stamp the firmware embeds in framebuffer bytes 762..767 (24-bit LE
//  sequence, CRC-16/CCITT-FALSE over bytes 0..761, 0x5A marker), and reconciles
//  host-side receipt counts against the device's own send counters.
//
//  Deliberately a separate ObservableObject from MIDIManager: frame verification
//  runs per message at up to free-run rates, so the live counters are plain vars
//  republished at 10 Hz — publishing them directly would invalidate the OLED
//  canvas on every frame.
//

import Foundation
import os.log

enum StressShape: UInt8, CaseIterable, Identifiable {
    case baseline = 0
    case messageRate = 1
    case bandwidth = 2
    case burst = 3
    case soak = 4
    case ramp = 5
    case visual = 6

    var id: UInt8 { rawValue }

    var label: String {
        switch self {
        case .baseline: return "S0 Baseline (one frame)"
        case .messageRate: return "S1 Message rate (tiny deltas)"
        case .bandwidth: return "S2 Bandwidth (full-span deltas)"
        case .burst: return "S3 Burst (on/off windows)"
        case .soak: return "S4 Soak (fixed rate, long)"
        case .ramp: return "S5 Ramp (finds the knee)"
        case .visual: return "S6 Visual (marquee)"
        }
    }

    var usesInterval: Bool { self != .baseline && self != .ramp }
}

struct StressHostStats {
    var messagesApplied = 0
    var messagesRejected = 0
    var bytesReceived = 0
    var framesObserved = 0
    var drops = 0
    var reorders = 0
    var crcFailures = 0
    var unstamped = 0
    var maxGapMs: Double = 0
    var gapsOver250 = 0
    /// Buckets: <20, 20–50, 50–100, 100–250, 250–1000, ≥1000 ms
    var gapBuckets = [Int](repeating: 0, count: 6)
    var lastSeq: UInt32?
    var lastFrameAt: Date?
    var runStartedAt: Date?
    /// (arrival, messageBytes) within the last few seconds, for windowed rates.
    var recentEvents: [(Date, Int)] = []

    var achievedFps: Double {
        rate(\.0) { _ in 1.0 }
    }

    var recentBytesPerSecond: Double {
        rate(\.0) { Double($0.1) }
    }

    private func rate(_ time: KeyPath<(Date, Int), Date>, _ weight: ((Date, Int)) -> Double) -> Double {
        guard let newest = recentEvents.last?.0, recentEvents.count >= 2 else { return 0 }
        let window = 2.0
        let cutoff = newest.addingTimeInterval(-window)
        let sum = recentEvents.filter { $0.0 >= cutoff }.reduce(0.0) { $0 + weight($1) }
        return sum / window
    }
}

struct StressDeviceStats {
    var framesRendered: UInt32 = 0
    var framesSkippedBudget: UInt32 = 0
    var deltaSent: UInt32 = 0
    var fullSent: UInt32 = 0
    var pushDeferredBuffer: UInt32 = 0
    var bytesQueued: UInt32 = 0
    var audioSampleTimer: UInt32 = 0
    var sendBufferSpace: UInt16 = 0
    var leaseRemainingMs: UInt16 = 0
    var activeShape: UInt8 = 0x7F
    var currentInterval: UInt8 = 0
    var asOf = Date.distantPast

    var messagesSent: Int { Int(deltaSent) + Int(fullSent) }
    var isIdle: Bool { activeShape == 0x7F }
}

@MainActor
class StressTester: ObservableObject {
    enum Phase: Equatable {
        case idle
        case starting
        case running
    }

    weak var midi: MIDIManager?

    // Run configuration (session-only, not persisted).
    @Published var shape: StressShape = .bandwidth
    @Published var intervalCs: Int = 3 // 10 ms units; 0 = free-run
    @Published var burstOnTenths: Int = 5 // S3 p1, 100 ms units
    @Published var burstOffTenths: Int = 5 // S3 p2, 100 ms units
    @Published var rampStepSecs: Int = 10 // S5 p1
    @Published var capSecs: Int = 600
    @Published var seedText: String = "" // empty = random per run

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusText: String = "Idle"
    @Published private(set) var lastSeedUsed: UInt32?
    // 10 Hz snapshots of the live counters, so per-frame work never publishes.
    @Published private(set) var host = StressHostStats()
    @Published private(set) var device: StressDeviceStats?

    private var live = StressHostStats()
    private var publishTimer: Timer?
    private var statsQueryTimer: Timer?
    private var ackDeadline: Timer?

    private let logger = Logger(subsystem: "com.delugedisplay", category: "StressTester")

    private var isCollecting: Bool { phase == .starting || phase == .running }

    // MARK: - Commands

    func start() {
        guard let midi, midi.isConnected else {
            statusText = "Not connected"
            return
        }
        guard phase == .idle else { return }

        let seed = resolveSeed()
        lastSeedUsed = seed
        var p1: UInt8 = 0
        var p2: UInt8 = 0
        switch shape {
        case .burst:
            p1 = UInt8(clamping: burstOnTenths)
            p2 = UInt8(clamping: burstOffTenths)
        case .ramp:
            p1 = UInt8(clamping: rampStepSecs)
        default:
            break
        }
        let interval = shape.usesInterval ? UInt8(clamping: intervalCs) : 0
        let cap = UInt32(clamping: capSecs) & 0x3FFF

        live = StressHostStats()
        live.runStartedAt = Date()
        host = live
        device = nil

        midi.sendStressSysEx([0xf0, 0x7d, 0x02, 0x03, 0x03, 0xf7]) // zero device counters first
        midi.sendStressSysEx([0xf0, 0x7d, 0x02, 0x03, 0x01,
                              shape.rawValue, interval, p1, p2,
                              UInt8(seed & 0x7f), UInt8((seed >> 7) & 0x7f),
                              UInt8((seed >> 14) & 0x7f), UInt8((seed >> 21) & 0x7f),
                              UInt8(cap & 0x7f), UInt8((cap >> 7) & 0x7f),
                              0xf7])
        phase = .starting
        statusText = "Starting…"
        armAckDeadline()
    }

    func stop() {
        guard let midi else { return }
        midi.sendStressSysEx([0xf0, 0x7d, 0x02, 0x03, 0x00, 0xf7])
    }

    func resetCounters() {
        midi?.sendStressSysEx([0xf0, 0x7d, 0x02, 0x03, 0x03, 0xf7])
        live = StressHostStats()
        live.runStartedAt = host.runStartedAt
        host = live
        device = nil
    }

    // MARK: - Replies (F0 7D 02 43 <sub> … F7)

    func handleReply(_ bytes: [UInt8]) {
        guard bytes.count >= 7, bytes[3] == 0x43 else { return }
        switch bytes[4] {
        case 0x00: // stop ack
            finishRun(status: bytes[5] == 0 ? "Stopped" : "Stop refused (status \(bytes[5]))")

        case 0x01: // start ack
            ackDeadline?.invalidate()
            ackDeadline = nil
            switch bytes[5] {
            case 0:
                phase = .running
                let seed = lastSeedUsed.map { String(format: "0x%07X", $0) } ?? "?"
                statusText = "Running (seed \(seed))"
                startTimers()
            case 1: failStart("Refused: bad parameters")
            case 2: failStart("Refused: device is playing/recording, or no push lease")
            case 3: failStart("Refused: no OLED on device")
            default: failStart("Refused (status \(bytes[5]))")
            }

        case 0x02: // stats
            guard bytes.count >= 8, bytes[5] == 0x01 else {
                logger.notice("Stress stats reply with unknown layout version \(bytes.count >= 6 ? bytes[5] : 0xff)")
                return
            }
            let payload = unpack7to8(Array(bytes[6...(bytes.count - 2)]))
            guard payload.count >= 34 else { return }
            var stats = StressDeviceStats()
            stats.framesRendered = readLE32(payload, 0)
            stats.framesSkippedBudget = readLE32(payload, 4)
            stats.deltaSent = readLE32(payload, 8)
            stats.fullSent = readLE32(payload, 12)
            stats.pushDeferredBuffer = readLE32(payload, 16)
            stats.bytesQueued = readLE32(payload, 20)
            stats.audioSampleTimer = readLE32(payload, 24)
            stats.sendBufferSpace = readLE16(payload, 28)
            stats.leaseRemainingMs = readLE16(payload, 30)
            stats.activeShape = payload[32]
            stats.currentInterval = payload[33]
            stats.asOf = Date()
            device = stats
            if phase == .running && stats.isIdle {
                finishRun(status: "Run ended on device (cap, local input, lease, or playback)")
            }

        default:
            break
        }
    }

    /// Called by MIDIManager for every OLED display SysEx it processed, with the
    /// reconstructed framebuffer when the message was applied cleanly.
    func noteDisplayMessage(applied: Bool, byteCount: Int, frame: [UInt8]?) {
        guard isCollecting else { return }
        let now = Date()
        if applied {
            live.messagesApplied += 1
        }
        else {
            live.messagesRejected += 1
        }
        live.bytesReceived += byteCount

        guard applied, let frame, frame.count == 768 else { return }
        guard frame[767] == 0x5A else {
            live.unstamped += 1
            return
        }
        let seq = UInt32(frame[762]) | (UInt32(frame[763]) << 8) | (UInt32(frame[764]) << 16)
        if seq == live.lastSeq {
            return // resync duplicate of a frame we already verified
        }
        let stored = UInt16(frame[765]) | (UInt16(frame[766]) << 8)
        if crc16CCITT(frame[0..<762]) != stored {
            live.crcFailures += 1
        }
        if let last = live.lastSeq {
            let forward = (seq &- last) & 0xFFFFFF
            if forward <= 0x800000 {
                live.drops += Int(forward) - 1
                live.lastSeq = seq
            }
            else {
                // Sequence went backwards: a late frame. Count it, keep the newest.
                live.reorders += 1
            }
        }
        else {
            live.lastSeq = seq
        }
        live.framesObserved += 1
        if let lastAt = live.lastFrameAt {
            let gapMs = now.timeIntervalSince(lastAt) * 1000
            live.maxGapMs = max(live.maxGapMs, gapMs)
            if gapMs > 250 { live.gapsOver250 += 1 }
            live.gapBuckets[bucketIndex(forGapMs: gapMs)] += 1
        }
        live.lastFrameAt = now
        live.recentEvents.append((now, byteCount))
        let cutoff = now.addingTimeInterval(-3)
        if let firstKept = live.recentEvents.firstIndex(where: { $0.0 >= cutoff }), firstKept > 0 {
            live.recentEvents.removeFirst(firstKept)
        }
    }

    // MARK: - Internals

    private func resolveSeed() -> UInt32 {
        let trimmed = seedText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let parsed: UInt32?
            if trimmed.lowercased().hasPrefix("0x") {
                parsed = UInt32(trimmed.dropFirst(2), radix: 16)
            }
            else {
                parsed = UInt32(trimmed)
            }
            if let parsed, parsed & 0x0FFF_FFFF != 0 {
                return parsed & 0x0FFF_FFFF
            }
        }
        return UInt32.random(in: 1..<(1 << 28))
    }

    private func armAckDeadline() {
        ackDeadline?.invalidate()
        ackDeadline = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .starting else { return }
                self.failStart("No reply from device")
            }
        }
    }

    private func failStart(_ message: String) {
        phase = .idle
        statusText = message
        stopTimers()
        host = live
    }

    private func finishRun(status: String) {
        guard phase != .idle else {
            statusText = status
            return
        }
        phase = .idle
        statusText = status
        stopTimers()
        host = live
        // One last stats query so the panel settles on the device's final counters.
        midi?.sendStressSysEx([0xf0, 0x7d, 0x02, 0x03, 0x02, 0xf7])
    }

    private func startTimers() {
        stopTimers()
        publishTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.host = self.live
            }
        }
        statsQueryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.midi?.sendStressSysEx([0xf0, 0x7d, 0x02, 0x03, 0x02, 0xf7])
            }
        }
    }

    private func stopTimers() {
        publishTimer?.invalidate()
        publishTimer = nil
        statsQueryTimer?.invalidate()
        statsQueryTimer = nil
        ackDeadline?.invalidate()
        ackDeadline = nil
    }

    private func bucketIndex(forGapMs gap: Double) -> Int {
        switch gap {
        case ..<20: return 0
        case ..<50: return 1
        case ..<100: return 2
        case ..<250: return 3
        case ..<1000: return 4
        default: return 5
        }
    }

    private func readLE32(_ data: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private func readLE16(_ data: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    /// Plain Sequential/DSI 7-to-8 unpacking, mirroring the firmware's
    /// unpack_7bit_to_8bit (util/pack.c): each 8-byte group is one high-bits byte
    /// followed by seven low-7-bit bytes.
    private func unpack7to8(_ src: [UInt8]) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity((src.count / 8) * 7 + 7)
        var i = 0
        while i < src.count {
            let highBits = src[i]
            var j = 0
            while j < 7 && i + 1 + j < src.count {
                var value = src[i + 1 + j] & 0x7f
                if highBits & (1 << j) != 0 {
                    value |= 0x80
                }
                out.append(value)
                j += 1
            }
            i += 8
        }
        return out
    }

    /// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF), as computed by the firmware
    /// over framebuffer bytes 0..761.
    private func crc16CCITT(_ data: ArraySlice<UInt8>) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }
}
