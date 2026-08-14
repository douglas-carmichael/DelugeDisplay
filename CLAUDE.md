# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

DelugeDisplay is a macOS SwiftUI app that mirrors the display of a Synthstrom Deluge groovebox over MIDI SysEx — either the 128×48 OLED or the 4-digit 7-segment display. Pure Apple frameworks (SwiftUI, AppKit, CoreMIDI, OSLog); no package manager and no third-party dependencies. Single app target `DelugeDisplay`, bundle id `net.dcarmich.DelugeDisplay`, deployment target macOS 15.4. Sandboxed with `device.usb` and `files.user-selected.read-write` entitlements (MIDI access + the screenshot save panel).

## Build & run

```sh
open DelugeDisplay.xcodeproj      # develop in Xcode; run with Cmd+R
xcodebuild -project DelugeDisplay.xcodeproj -scheme DelugeDisplay -configuration Debug build
```

- **There is no test target, linter, or formatter** — don't look for or invent test commands. Verification is manual: build and run against a Deluge connected via MIDI (without hardware you can still confirm the app builds and shows the "WAITING FOR DELUGE" banner).
- App version is `MARKETING_VERSION` in `project.pbxproj` (update both Debug and Release blocks).
- Releases are hand-distributed as .dmg/.zip via GitHub Releases; there is no CI in this repo.

## Branches

- `main` — uses the firmware's **subscription/push** display mode: the app renews a 2 s lease and the Deluge pushes RLE deltas only when its screen changes, with periodic and on-error full-image resyncs on the app side. (Historically `main` was full-frame polling "for Ethernet compatibility"; the delta failures behind that rule were traced to since-fixed transport bugs in this app — `MIDIPacketList` value-copying, chunk reordering, interleaved-message corruption — not to the delta protocol. An old `ios-delta` experiment branch was superseded by this and deleted.)

## Architecture

Everything flows through **`MIDIManager`** (`MIDIManager.swift`), a `@MainActor ObservableObject` owning all non-view state: the CoreMIDI client/ports, port scanning and auto/re-connect, the SysEx protocol, the connection state machine, and the published display state (`frameBuffer`, `sevenSegmentDigits`/`sevenSegmentDots`, `isConnected`, plus user prefs — display mode, color mode, smoothing, pixel grid). `DelugeDisplayApp` creates it as a `@StateObject` and injects it with `.environmentObject`; views read it and set properties on it, never talk MIDI themselves.

### MIDIManager is a single, shared instance
`DelugeDisplayApp` owns the only `MIDIManager` (`@StateObject`) and hands it to `AppDelegate` via `.onAppear` (`appDelegate.midiManager`), whose `applicationWillTerminate` disconnect acts on it. Never construct a second manager — a second instance opens its own CoreMIDI client that connects and subscribes to the Deluge in parallel.

### SysEx protocol (manufacturer id 0x7D)
Requests (constants at the bottom of `MIDIManager`):
- `F0 7D 02 00 02 F7` — subscribe/renew the display push lease (2 s on the firmware side); `F0 7D 02 00 03 F7` — same, but forces a full-image resend. Steady state is renewals only; forces are deliberately rare (see lifecycle §3).
- `F0 7D 02 00 01 F7` — request one full OLED frame (connection probe / `connectionTimer`)
- `F0 7D 02 01 00 F7` — request 7-segment data (probe)
- `F0 7D 02 00 04 F7` — toggle which display the Deluge hardware shows (sent on every mode switch)

Responses (parsed in `processSysExMessage`; bytes are reassembled between `F0`/`F7` in `reassembleSysEx` on `processQueue`, which skips interleaved realtime bytes and whole channel/system-common messages):
- OLED full image: `F0 7D 02 40 01 00 …` — payload from byte 6 is RLE-packed; `unpack7to8RLE` (`RLEDecoder.swift`) must expand it to exactly 768 bytes or a resync is scheduled.
- OLED delta (push): `F0 7D 02 40 02 <start> <len> …` — start/len in 8-byte units into the 768-byte buffer; payload from byte 7 must unpack to exactly `8*len` bytes or a resync is scheduled.
- 7-seg: exactly 12 bytes, `F0 7D 02 41 …` — byte 6 is the dot bitmask, bytes 7–10 the segment bitmasks for the 4 digits (bit 6 → segment A … bit 0 → segment G, decoded in `SevenSegmentDigitView`).

Frame buffer layout (SSD1306-style pages): 768 bytes = 6 blocks × 128 columns; each byte is a vertical 8-pixel strip, `byteIndex = block * 128 + col`, bit n = row within the block.

### Stress test panel (display SysEx family 0x03)
Host side of the firmware's display link stress exerciser (spec: `docs/deluge-firmware-spec-display-midi-exerciser.md`; firmware branch `feature/display-stress-exerciser`). MIDI menu → "Stress Test…" (⇧⌘T) opens a `Window` scene backed by `StressTester` (model, owned lazily by `MIDIManager`) + `StressTestView`.
- Requests `F0 7D 02 03 <sub> … F7`: `00` stop, `01` start (`shape, interval, p1, p2, seed[4], capSecs[2]`, all LSB-first 7-bit), `02` query stats, `03` reset stats. Replies `F0 7D 02 43 <sub> …`: acks carry a status byte (0 ok / 1 bad param / 2 refused / 3 no OLED); stats carry a layout-version byte then a `pack_8bit_to_7bit` payload (plain Sequential packing — decoded by `StressTester.unpack7to8`, distinct from the RLE codec).
- During a run the firmware stamps framebuffer bytes 762–767 (24-bit LE sequence, CRC-16/CCITT-FALSE over bytes 0..761, `0x5A` marker). `processSysExMessage` reports every OLED message to `stressTester.noteDisplayMessage`, which verifies stamps on the reconstructed buffer: sequence gaps = drops, CRC mismatch = corruption/desync, regression = reorder. Device counters are polled at 1 Hz and reconciled against host receipt counts.
- `StressTester` is deliberately a **separate ObservableObject**: per-frame counters are plain vars republished at 10 Hz, because any `@Published` churn on `MIDIManager` invalidates the OLED canvas.

### Connection lifecycle (all timer-driven, inside MIDIManager)
1. Port selection (`selectedPort.didSet`) → `connectToDeluge` resolves input/output endpoints by port *name*.
2. `startDisplayModeProbe`: request OLED, 0.5 s timeout → request 7-seg, 0.5 s timeout → fall back to the saved mode. The first response wins and sets the initial mode; receiving any valid frame is what flips `isConnected`.
3. A repeating 50 ms `updateTimer` maintains the subscription: renews the lease every 1 s, forces a full-image resync every 5 min or after any rejected delta, and logs a notice (in release builds too) when a forced resync goes unanswered, retrying with exponential backoff (5 s → 60 s, reset on any received frame). **Full-image forces must stay rare and spaced out**: repeated force/full-image-reply cycles trip macOS 26 CoreMIDI's feedback-loop detector, which mutes the Deluge's source for 10–25 s at a time (`MIDIServer` logs "feedback loop from MIDI source") — the cause of the Aug 2026 playback-stall bug. Steady-state renewals + deltas and isolated single forces never trip it. A 2 s `connectionTimer` retries connection, and CoreMIDI change notifications rescan ports / reconnect the remembered port.
4. `displayLogicGeneration` (bumped on every mode change) is captured by timers and re-checked when they fire, so timers from a previous mode become no-ops. **Any change to mode switching or timers must respect this generation guard.** The 7SEG→OLED transition additionally waits 75 ms after sending the toggle before requesting data (see `displayMode.didSet` — the trickiest code in the app).

### Rendering
- `ContentView` switches between `DelugeScreenView` (OLED), `SevenSegmentDisplayView` (7-seg), and a "WAITING FOR DELUGE" banner drawn with `DelugeFont` (a hand-defined 5×7 bitmap font) when disconnected.
- The OLED live view is a SwiftUI `Canvas` that accumulates every lit pixel into a single `Path` and fills it with one draw call (`OLEDViewContent`) — per-pixel fills stall the RenderBox encoder queue — with optional pixel-grid insets and blur-based "smoothing". Screenshots go through a **separate, duplicated** CGContext path (`createCGImageForScreenshot`); 7-seg screenshots use `ImageRenderer`.
- **`DelugeDisplayColorMode` colors are re-derived independently in 5 places**: the OLED canvas, the OLED screenshot path (`createCGImageForScreenshot`), `SevenSegmentDisplayView`, the `ContentView` background, and the `DelugeFont` call site. Adding or changing a color mode means updating all of them.
- Menus live in `DelugeDisplayApp.commands` (the View menu replaces `.sidebar`; a custom MIDI menu lists ports as toggles). Window behavior — minimum size, hard 8:3 aspect ratio, zoom commands — is `AppDelegate` acting as window delegate.

## Conventions

- Logging is OSLog: `Logger(subsystem: "com.delugedisplay", category: <TypeName>)`, with nearly every call wrapped in `#if DEBUG`. Follow that pattern.
- User prefs persist via `UserDefaults.standard` writes inside the `didSet` of the corresponding `@Published` property, and are read back in `MIDIManager.init`. New prefs should do the same.
- All MIDI/display state mutation happens on the MainActor; CoreMIDI callbacks hop over via `Task { @MainActor … }`.
