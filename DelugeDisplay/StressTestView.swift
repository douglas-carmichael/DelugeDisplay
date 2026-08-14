//
//  StressTestView.swift
//  DelugeDisplay
//
//  Control panel for the firmware's display link stress exerciser: pick a load
//  shape, start/stop a run, and watch host-side verification (frames, drops,
//  CRC failures, gaps) reconciled live against the device's own send counters.
//

import SwiftUI

struct StressTestView: View {
    @EnvironmentObject private var midiManager: MIDIManager

    var body: some View {
        StressTestPanel(tester: midiManager.stressTester, midiManager: midiManager)
    }
}

private struct StressTestPanel: View {
    @ObservedObject var tester: StressTester
    @ObservedObject var midiManager: MIDIManager

    private var isRunning: Bool { tester.phase != .idle }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            configurationSection
            controlRow
            Divider()
            HStack(alignment: .top, spacing: 12) {
                hostSection
                deviceSection
            }
            reconciliationSection
        }
        .padding(16)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var configurationSection: some View {
        GroupBox("Load shape") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Shape", selection: $tester.shape) {
                    ForEach(StressShape.allCases) { shape in
                        Text(shape.label).tag(shape)
                    }
                }
                .disabled(isRunning)

                if tester.shape.usesInterval {
                    HStack {
                        Stepper(value: $tester.intervalCs, in: 0...127) {
                            Text("Interval: \(tester.intervalCs == 0 ? "free-run" : "\(tester.intervalCs * 10) ms")")
                        }
                        if tester.intervalCs > 0 {
                            Text(String(format: "≈ %.1f fps", 100.0 / Double(tester.intervalCs)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isRunning)
                }

                if tester.shape == .burst {
                    HStack(spacing: 16) {
                        Stepper(value: $tester.burstOnTenths, in: 1...127) {
                            Text(String(format: "On: %.1f s", Double(tester.burstOnTenths) / 10))
                        }
                        Stepper(value: $tester.burstOffTenths, in: 1...127) {
                            Text(String(format: "Off: %.1f s", Double(tester.burstOffTenths) / 10))
                        }
                    }
                    .disabled(isRunning)
                }

                if tester.shape == .ramp {
                    Stepper(value: $tester.rampStepSecs, in: 1...127) {
                        Text("Ramp step: \(tester.rampStepSecs) s (500 ms halving to free-run)")
                    }
                    .disabled(isRunning)
                }

                HStack(spacing: 16) {
                    Stepper(value: $tester.capSecs, in: 10...16383, step: 10) {
                        Text("Cap: \(tester.capSecs) s")
                    }
                    TextField("Seed (blank = random)", text: $tester.seedText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                }
                .disabled(isRunning)
            }
            .padding(4)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            Button("Start") { tester.start() }
                .disabled(!midiManager.isConnected || isRunning)
                .keyboardShortcut(.defaultAction)
            Button("Stop") { tester.stop() }
                .disabled(!midiManager.isConnected || !isRunning)
            Button("Reset Counters") { tester.resetCounters() }
                .disabled(!midiManager.isConnected || isRunning)
            Spacer()
            Text(midiManager.isConnected ? tester.statusText : "Not connected")
                .foregroundStyle(isRunning ? Color.green : Color.secondary)
                .lineLimit(1)
        }
    }

    private var hostSection: some View {
        GroupBox("Host (verified from frame stamps)") {
            statGrid([
                ("Frames observed", "\(tester.host.framesObserved)"),
                ("Rate", String(format: "%.1f fps · %.1f KB/s", tester.host.achievedFps,
                                tester.host.recentBytesPerSecond / 1000)),
                ("Dropped (seq gaps)", "\(tester.host.drops)"),
                ("CRC failures", "\(tester.host.crcFailures)"),
                ("Reordered", "\(tester.host.reorders)"),
                ("Unstamped frames", "\(tester.host.unstamped)"),
                ("Messages applied", "\(tester.host.messagesApplied)"),
                ("Messages rejected", "\(tester.host.messagesRejected)"),
                ("Bytes received", "\(tester.host.bytesReceived)"),
                ("Max gap", String(format: "%.0f ms", tester.host.maxGapMs)),
                ("Gaps > 250 ms", "\(tester.host.gapsOver250)"),
                ("Gap buckets", gapBucketText),
            ])
        }
    }

    private var deviceSection: some View {
        GroupBox("Device (SysEx stats query)") {
            if let device = tester.device {
                statGrid([
                    ("Frames rendered", "\(device.framesRendered)"),
                    ("Skipped (budget)", "\(device.framesSkippedBudget)"),
                    ("Deltas sent", "\(device.deltaSent)"),
                    ("Fulls sent", "\(device.fullSent)"),
                    ("Pushes deferred", "\(device.pushDeferredBuffer)"),
                    ("Bytes queued", "\(device.bytesQueued)"),
                    ("Send buffer space", "\(device.sendBufferSpace)"),
                    ("Lease remaining", "\(device.leaseRemainingMs) ms"),
                    ("Active shape", device.isIdle ? "idle" : "S\(device.activeShape)"),
                    ("Current interval", device.currentInterval == 0
                        ? "free-run" : "\(Int(device.currentInterval) * 10) ms"),
                ])
            }
            else {
                Text("No stats yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
        }
    }

    private var reconciliationSection: some View {
        GroupBox("Reconciliation") {
            VStack(alignment: .leading, spacing: 4) {
                if let device = tester.device {
                    let sent = device.messagesSent
                    let received = tester.host.messagesApplied + tester.host.messagesRejected
                    let lost = sent - received
                    let collapsed = Int(device.framesRendered) - sent
                    Text(lost > 0
                         ? "Link lost ≈ \(lost) of \(sent) display messages the device sent."
                         : "Link delivered all \(sent) display messages the device sent.")
                    Text(collapsed > 0
                         ? "Device collapsed ≈ \(collapsed) rendered frames before sending (throttle/coalescing)."
                         : "Every rendered frame went out as its own message.")
                        .foregroundStyle(.secondary)
                }
                else {
                    Text("Runs once device stats arrive (queried every second during a run).")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var gapBucketText: String {
        let labels = ["<20", "<50", "<100", "<250", "<1s", "≥1s"]
        return zip(labels, tester.host.gapBuckets)
            .map { "\($0.0):\($0.1)" }
            .joined(separator: " ")
    }

    private func statGrid(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Text(row.1)
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
    }
}
