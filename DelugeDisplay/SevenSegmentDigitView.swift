import SwiftUI

struct SevenSegmentDigitView: View {
    let digitPattern: UInt8
    let dotActive: Bool
    let activeColor: Color
    let inactiveColor: Color
    let scale: CGFloat // To allow the parent to control the size

    // Segment paths (A-G, and Dot)
    // Segments are typically indexed:
    //   --A--
    //  |     |
    //  F     B
    //  |     |
    //   --G--
    //  |     |
    //  E     C
    //  |     |
    //   --D--   . DP

    // From app.js, mapping seems to be (bit index to segment letter, needs verification):
    // Bit 0: G (midline)
    // Bit 1: F (top-left vertical)
    // Bit 2: E (bottom-left vertical)
    // Bit 3: D (bottom horizontal)
    // Bit 4: C (bottom-right vertical)
    // Bit 5: B (top-right vertical)
    // Bit 6: A (top horizontal)
    // This order (G,F,E,D,C,B,A) is a bit unusual but we'll follow what app.js implies.

    // Dimensions from app.js, adapted for SwiftUI and scaling
    // Original fixed dimensions:
    // const digit_height = 120 * scale; (overall height for calculations)
    // const digit_width = 60 * scale;  (overall width for calculations)
    // const stroke_thick = 9 * scale;
    // const half_height = digit_height / 2;
    // const out_adj = 0.5 * scale;
    // const in_adj = 1.5 * scale;
    // const dot_size = 6.5 * scale;

    // We'll define canonical dimensions (e.g., for a 60x120 digit box) and scale them.
    private var digitDrawingWidth: CGFloat { 60 * scale }
    private var digitDrawingHeight: CGFloat { 120 * scale }
    private var strokeThickness: CGFloat { 9 * scale }
    private var dotSize: CGFloat { 7 * scale } // Slightly adjusted from 6.5

    var body: some View {
        ZStack {
            // Segment A (Top)
            SegmentShape(pathDefinition: segmentPath(for: .A))
                .fill(isSegmentActive(0x40) ? activeColor : inactiveColor) // Bit 6

            // Segment B (Top-Right)
            SegmentShape(pathDefinition: segmentPath(for: .B))
                .fill(isSegmentActive(0x20) ? activeColor : inactiveColor) // Bit 5

            // Segment C (Bottom-Right)
            SegmentShape(pathDefinition: segmentPath(for: .C))
                .fill(isSegmentActive(0x10) ? activeColor : inactiveColor) // Bit 4

            // Segment D (Bottom)
            SegmentShape(pathDefinition: segmentPath(for: .D))
                .fill(isSegmentActive(0x08) ? activeColor : inactiveColor) // Bit 3

            // Segment E (Bottom-Left)
            SegmentShape(pathDefinition: segmentPath(for: .E))
                .fill(isSegmentActive(0x04) ? activeColor : inactiveColor) // Bit 2

            // Segment F (Top-Left)
            SegmentShape(pathDefinition: segmentPath(for: .F))
                .fill(isSegmentActive(0x02) ? activeColor : inactiveColor) // Bit 1
            
            // Segment G (Middle)
            SegmentShape(pathDefinition: segmentPath(for: .G))
                .fill(isSegmentActive(0x01) ? activeColor : inactiveColor) // Bit 0

            // Dot (DP)
            if dotActive {
                Circle()
                    .fill(activeColor)
                    .frame(width: dotSize, height: dotSize)
                    // Position dot to the bottom right of the digit area
                    .offset(x: digitDrawingWidth / 2 + dotSize / 2 + (2 * scale), y: digitDrawingHeight / 2 - dotSize / 2)
            }
        }
        .frame(width: digitDrawingWidth + dotSize + (4*scale), height: digitDrawingHeight) // Ensure frame accommodates dot
        .drawingGroup() // Improves performance for complex drawings
    }

    private func isSegmentActive(_ mask: UInt8) -> Bool {
        (digitPattern & mask) != 0
    }

    private enum Segment {
        case A, B, C, D, E, F, G
    }

    private func segmentPath(for segment: Segment) -> Path {
        var path = Path()
        let w = digitDrawingWidth
        let h = digitDrawingHeight
        let st = strokeThickness
        
        let topY = -h/2 + st/2
        let midY = CGFloat(0)
        let botY = h/2 - st/2
        
        let leftX = -w/2 + st/2
        let rightX = w/2 - st/2

        let segmentLengthHorizontal = w - st 
        let segmentLengthVertical = h/2 - st 

        switch segment {
        case .A: 
            path.move(to: CGPoint(x: -segmentLengthHorizontal/2 + st/2, y: topY))
            path.addLine(to: CGPoint(x: segmentLengthHorizontal/2 - st/2, y: topY))
            return Path(CGRect(x: -segmentLengthHorizontal/2 + st/2, y: topY - st/2, width: segmentLengthHorizontal - st, height: st))
        case .G: 
            path.move(to: CGPoint(x: -segmentLengthHorizontal/2 + st/2, y: midY))
            path.addLine(to: CGPoint(x: segmentLengthHorizontal/2 - st/2, y: midY))
            return Path(CGRect(x: -segmentLengthHorizontal/2 + st/2, y: midY - st/2, width: segmentLengthHorizontal - st, height: st))
        case .D: 
            path.move(to: CGPoint(x: -segmentLengthHorizontal/2 + st/2, y: botY))
            path.addLine(to: CGPoint(x: segmentLengthHorizontal/2 - st/2, y: botY))
            return Path(CGRect(x: -segmentLengthHorizontal/2 + st/2, y: botY - st/2, width: segmentLengthHorizontal - st, height: st))
        
        case .F: 
            path.move(to: CGPoint(x: leftX, y: topY + st/2))
            path.addLine(to: CGPoint(x: leftX, y: midY - st/2))
            return Path(CGRect(x: leftX - st/2, y: topY + st/2, width: st, height: segmentLengthVertical - st))
        case .B: 
            path.move(to: CGPoint(x: rightX, y: topY + st/2))
            path.addLine(to: CGPoint(x: rightX, y: midY - st/2))
            return Path(CGRect(x: rightX - st/2, y: topY + st/2, width: st, height: segmentLengthVertical - st))

        case .E: 
            path.move(to: CGPoint(x: leftX, y: midY + st/2))
            path.addLine(to: CGPoint(x: leftX, y: botY - st/2))
            return Path(CGRect(x: leftX - st/2, y: midY + st/2, width: st, height: segmentLengthVertical - st))
        case .C: 
            path.move(to: CGPoint(x: rightX, y: midY + st/2))
            path.addLine(to: CGPoint(x: rightX, y: botY - st/2))
            return Path(CGRect(x: rightX - st/2, y: midY + st/2, width: st, height: segmentLengthVertical - st))
        }
    }
}

// Helper struct to draw a segment as a shape from a Path
struct SegmentShape: Shape {
    let pathDefinition: Path

    func path(in rect: CGRect) -> Path {
        // The pathDefinition is already in its local coordinate space.
        // We need to offset it to be centered in the rect.
        let offsetX = rect.midX
        let offsetY = rect.midY
        return pathDefinition.applying(CGAffineTransform(translationX: offsetX, y: offsetY))
    }
}

struct SevenSegmentDigitView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Test all digits 0-9 and some letters
            HStack {
                SevenSegmentDigitView(digitPattern: 0b01111110, dotActive: false, activeColor: .red, inactiveColor: .gray.opacity(0.2), scale: 0.5) // 0
                SevenSegmentDigitView(digitPattern: 0b00110000, dotActive: true, activeColor: .red, inactiveColor: .gray.opacity(0.2), scale: 0.5)  // 1
                SevenSegmentDigitView(digitPattern: 0b01101101, dotActive: false, activeColor: .red, inactiveColor: .gray.opacity(0.2), scale: 0.5) // 2
                SevenSegmentDigitView(digitPattern: 0b01111001, dotActive: false, activeColor: .red, inactiveColor: .gray.opacity(0.2), scale: 0.5) // 3
            }
            HStack {
                SevenSegmentDigitView(digitPattern: 0b00110011, dotActive: false, activeColor: .orange, inactiveColor: .gray.opacity(0.2), scale: 0.5) // 4
                SevenSegmentDigitView(digitPattern: 0b01011011, dotActive: true, activeColor: .orange, inactiveColor: .gray.opacity(0.2), scale: 0.5)  // 5
                SevenSegmentDigitView(digitPattern: 0b01011111, dotActive: false, activeColor: .orange, inactiveColor: .gray.opacity(0.2), scale: 0.5) // 6
                SevenSegmentDigitView(digitPattern: 0b01110000, dotActive: false, activeColor: .orange, inactiveColor: .gray.opacity(0.2), scale: 0.5) // 7
            }
            HStack {
                SevenSegmentDigitView(digitPattern: 0b01111111, dotActive: false, activeColor: .yellow, inactiveColor: .gray.opacity(0.2), scale: 0.5) // 8
                SevenSegmentDigitView(digitPattern: 0b01111011, dotActive: true, activeColor: .yellow, inactiveColor: .gray.opacity(0.2), scale: 0.5)  // 9
                SevenSegmentDigitView(digitPattern: 0b01110111, dotActive: false, activeColor: .green, inactiveColor: .gray.opacity(0.2), scale: 0.5) // A
                SevenSegmentDigitView(digitPattern: 0b00011111, dotActive: false, activeColor: .blue, inactiveColor: .gray.opacity(0.2), scale: 0.5) // b
            }
             HStack {
                SevenSegmentDigitView(digitPattern: 0b01001110, dotActive: false, activeColor: .purple, inactiveColor: .gray.opacity(0.2), scale: 0.5) // C
                SevenSegmentDigitView(digitPattern: 0b00111101, dotActive: true, activeColor: .pink, inactiveColor: .gray.opacity(0.2), scale: 0.5)  // d
                SevenSegmentDigitView(digitPattern: 0b01001111, dotActive: false, activeColor: .cyan, inactiveColor: .gray.opacity(0.2), scale: 0.5) // E
                SevenSegmentDigitView(digitPattern: 0b01000111, dotActive: false, activeColor: .mint, inactiveColor: .gray.opacity(0.2), scale: 0.5) // F
            }
            SevenSegmentDigitView(digitPattern: 0b00000000, dotActive: true, activeColor: .red, inactiveColor: .gray.opacity(0.2), scale: 1.0) // Blank with dot
        }
        .padding()
        .background(Color.black)
    }
}
