
import SwiftUI

struct SevenSegmentDisplayView: View {
    @EnvironmentObject var midiManager: MIDIManager
    
    // Constants for display layout
    private let digitSpacing: CGFloat = 10 // Spacing between digits
    private let displayScale: CGFloat = 0.7 // Overall scale of the digits

    var body: some View {
        HStack(spacing: digitSpacing) {
            // Ensure we have 4 digits, provide defaults if not
            let digits = midiManager.sevenSegmentDigits
            let d1 = digits.count > 0 ? digits[0] : 0
            let d2 = digits.count > 1 ? digits[1] : 0
            let d3 = digits.count > 2 ? digits[2] : 0
            let d4 = digits.count > 3 ? digits[3] : 0

            // Dots mapping: app.js `(dots & (1 << d)) != 0`
            // Assuming d=0 is the rightmost digit in app.js, and d=3 is leftmost.
            // In our array, index 0 is leftmost, index 3 is rightmost.
            // So, dot for digits[0] (d1) would be (dots & (1 << 3)) or (dots & 0x08)
            // dot for digits[1] (d2) would be (dots & (1 << 2)) or (dots & 0x04)
            // dot for digits[2] (d3) would be (dots & (1 << 1)) or (dots & 0x02)
            // dot for digits[3] (d4) would be (dots & (1 << 0)) or (dots & 0x01)
            // This needs to be confirmed against how Deluge sends dot data.
            // The app.js `draw7Seg(data.subarray(7,11), data[6])` passes `data[6]` as `dots`.
            // `for (let d = 0; d < 4; d++) { let dot = (dots & (1 << d)) != 0; }`
            // If `d=0` in JS corresponds to `digits[0]` (leftmost), then bit 0 is for leftmost.

            // Let's assume for now that bit 0 of `sevenSegmentDots` corresponds to `digits[0]` (leftmost),
            // bit 1 to `digits[1]`, etc. This is often how it's done.
            // If it's reversed (bit 0 for rightmost), the masks will need to be swapped.

            let dot1Active = (midiManager.sevenSegmentDots & (1 << 0)) != 0 // For digits[0]
            let dot2Active = (midiManager.sevenSegmentDots & (1 << 1)) != 0 // For digits[1]
            let dot3Active = (midiManager.sevenSegmentDots & (1 << 2)) != 0 // For digits[2]
            let dot4Active = (midiManager.sevenSegmentDots & (1 << 3)) != 0 // For digits[3]

            // Determine colors based on midiManager.displayColorMode
            let activeColor: Color
            let inactiveColor: Color
            
            // From app.js:
            // const activeColor = displaySettings.use7SegCustomColors ? displaySettings.foregroundColor : "#CC3333";
            // const inactiveColor = displaySettings.use7SegCustomColors ? displaySettings.backgroundColor : "#331111";
            // For now, let's use fixed LED-like colors, but ideally, this would respect DelugeDisplayColorMode
            // or have its own settings.
            // We can use the existing displayColorMode for simplicity initially.
            
            switch midiManager.displayColorMode {
            case .normal: // White on Black for OLED -> Red on Dark Red for 7-Seg
                activeColor = .red
                inactiveColor = Color(red: 0.2, green: 0, blue: 0) // Dark red
            case .inverted: // Black on White for OLED -> Dark Red on Red for 7-Seg (less common)
                activeColor = Color(red: 0.2, green: 0, blue: 0)
                inactiveColor = .red
            }

            SevenSegmentDigitView(digitPattern: d1, dotActive: dot1Active, activeColor: activeColor, inactiveColor: inactiveColor, scale: displayScale)
            SevenSegmentDigitView(digitPattern: d2, dotActive: dot2Active, activeColor: activeColor, inactiveColor: inactiveColor, scale: displayScale)
            SevenSegmentDigitView(digitPattern: d3, dotActive: dot3Active, activeColor: activeColor, inactiveColor: inactiveColor, scale: displayScale)
            SevenSegmentDigitView(digitPattern: d4, dotActive: dot4Active, activeColor: activeColor, inactiveColor: inactiveColor, scale: displayScale)
        }
        .padding()
        .background(Color.black) // Overall background for the 7-segment display area
        .cornerRadius(10)
    }
}

struct SevenSegmentDisplayView_Previews: PreviewProvider {
    static func getPreviewMIDIManager(digits: [UInt8], dots: UInt8, mode: DelugeDisplayColorMode = .normal) -> MIDIManager {
        let manager = MIDIManager()
        manager.sevenSegmentDigits = digits
        manager.sevenSegmentDots = dots
        manager.displayMode = .sevenSegment // Important for context
        manager.displayColorMode = mode
        manager.isConnected = true // Simulate connection for preview
        return manager
    }

    static var previews: some View {
        VStack {
            Text("7-Segment Preview (Normal)")
            SevenSegmentDisplayView()
                .environmentObject(getPreviewMIDIManager(digits: [
                    0b01111110, // 0
                    0b00110000, // 1
                    0b01101101, // 2
                    0b01111001  // 3
                ], dots: 0b0101)) // Dots for 2nd and 4th digit (from left)
                .frame(height: 150)

            Text("7-Segment Preview (Inverted)")
            SevenSegmentDisplayView()
                .environmentObject(getPreviewMIDIManager(digits: [
                    0b00110011, // 4
                    0b01011011, // 5
                    0b01011111, // 6
                    0b01110000  // 7
                ], dots: 0b1010, mode: .inverted)) // Dots for 1st and 3rd
                .frame(height: 150)
            
            Text("Live Data Preview (Connect Deluge & set to 7-Seg)")
            SevenSegmentDisplayView()
                .environmentObject(MIDIManager()) // For live testing if Deluge is connected
                .frame(height: 150)
        }
        .padding()
    }
}
