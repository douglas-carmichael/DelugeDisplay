import SwiftUI

struct SevenSegmentDisplayView: View {
    @EnvironmentObject var midiManager: MIDIManager
    let availableSize: CGSize

    private let intrinsicDigitWidth: CGFloat = 60
    private let intrinsicDigitHeight: CGFloat = 120
    private let digitSpacing: CGFloat = 10

    private var activeColor: Color {
        switch midiManager.displayColorMode {
        case .normal: return .red
        case .inverted: return .black 
        }
    }

    private var inactiveColor: Color {
        switch midiManager.displayColorMode {
        case .normal: return Color(red: 0.2, green: 0, blue: 0)
        case .inverted: return .white
        }
    }

    private var backgroundColor: Color {
        switch midiManager.displayColorMode {
        case .normal: return .black
        case .inverted: return .white
        }
    }

    var body: some View {
        let calculatedScale: CGFloat = {
            let paddingSize: CGFloat = 16 * 2
            let effectiveWidth = max(0, availableSize.width - paddingSize)
            let effectiveHeight = max(0, availableSize.height - paddingSize)
            let totalIntrinsicWidthForDigits = (4 * intrinsicDigitWidth) + (3 * digitSpacing)
            let totalIntrinsicHeightForDigits = intrinsicDigitHeight
            guard totalIntrinsicWidthForDigits > 0, totalIntrinsicHeightForDigits > 0 else {
                return 0.7
            }
            let scaleBasedOnWidth = effectiveWidth / totalIntrinsicWidthForDigits
            let scaleBasedOnHeight = effectiveHeight / totalIntrinsicHeightForDigits
            return min(scaleBasedOnWidth, scaleBasedOnHeight)
        }()

        let blurRadius: CGFloat = {
            if !midiManager.smoothingEnabled {
                return 0
            }
            let baseLow: CGFloat = 0.8
            let baseMedium: CGFloat = 1.5
            let baseHigh: CGFloat = 2.5
            
            var effectiveRadius: CGFloat = 0
            switch midiManager.smoothingQuality {
            case .low: effectiveRadius = baseLow
            case .medium: effectiveRadius = baseMedium
            case .high: effectiveRadius = baseHigh
            case .none: effectiveRadius = 0
            @unknown default: effectiveRadius = baseMedium
            }
            return effectiveRadius * calculatedScale
        }()

        GeometryReader { geometryProxy in
            HStack(spacing: digitSpacing * calculatedScale) {
                let digits = midiManager.sevenSegmentDigits
                let d1 = digits.count > 0 ? digits[0] : 0
                let d2 = digits.count > 1 ? digits[1] : 0
                let d3 = digits.count > 2 ? digits[2] : 0
                let d4 = digits.count > 3 ? digits[3] : 0

                let dot1Active = (midiManager.sevenSegmentDots & (1 << 0)) != 0
                let dot2Active = (midiManager.sevenSegmentDots & (1 << 1)) != 0
                let dot3Active = (midiManager.sevenSegmentDots & (1 << 2)) != 0
                let dot4Active = (midiManager.sevenSegmentDots & (1 << 3)) != 0

                SevenSegmentDigitView(digitPattern: d1, dotActive: dot1Active, activeColor: activeColor, inactiveColor: inactiveColor, scale: calculatedScale)
                SevenSegmentDigitView(digitPattern: d2, dotActive: dot2Active, activeColor: activeColor, inactiveColor: inactiveColor, scale: calculatedScale)
                SevenSegmentDigitView(digitPattern: d3, dotActive: dot3Active, activeColor: activeColor, inactiveColor: inactiveColor, scale: calculatedScale)
                SevenSegmentDigitView(digitPattern: d4, dotActive: dot4Active, activeColor: activeColor, inactiveColor: inactiveColor, scale: calculatedScale)
            }
            .frame(width: geometryProxy.size.width, height: geometryProxy.size.height)
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(10)
        .blur(radius: blurRadius)
    }
}

struct SevenSegmentDisplayView_Previews: PreviewProvider {
    static func getPreviewMIDIManager(digits: [UInt8], dots: UInt8, mode: DelugeDisplayColorMode = .normal) -> MIDIManager {
        let manager = MIDIManager()
        manager.sevenSegmentDigits = digits
        manager.sevenSegmentDots = dots
        manager.displayMode = .sevenSegment
        manager.displayColorMode = mode
        manager.isConnected = true
        return manager
    }

    static var previews: some View {
        VStack {
            Text("7-Segment Preview (Normal)")
            SevenSegmentDisplayView(availableSize: CGSize(width: 400, height: 150))
                .environmentObject(getPreviewMIDIManager(digits: [
                    0b01111110, 0b00110000, 0b01101101, 0b01111001
                ], dots: 0b0101))
                .frame(width: 400, height: 150)
                .background(Color.gray)

            Text("7-Segment Preview (Inverted)")
            SevenSegmentDisplayView(availableSize: CGSize(width: 300, height: 100))
                .environmentObject(getPreviewMIDIManager(digits: [
                    0b00110011, 0b01011011, 0b01011111, 0b01110000
                ], dots: 0b1010, mode: .inverted))
                .frame(width: 300, height: 100)
                .background(Color.gray)
            
            Text("Live Data Preview (Placeholder - Use App)")
             SevenSegmentDisplayView(availableSize: CGSize(width: 350, height: 120))
                 .environmentObject(MIDIManager())
                 .frame(width: 350, height: 120)
        }
        .padding()
    }
}
