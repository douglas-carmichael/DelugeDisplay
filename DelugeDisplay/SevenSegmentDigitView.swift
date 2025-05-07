import SwiftUI

struct SevenSegmentDigitView: View {
    let digitPattern: UInt8
    let dotActive: Bool
    let activeColor: Color
    let inactiveColor: Color
    let scale: CGFloat 

    private var digitDrawingWidth: CGFloat { 60 * scale }
    private var digitDrawingHeight: CGFloat { 120 * scale }
    private var strokeThickness: CGFloat { 9 * scale }
    private var dotSize: CGFloat { 7 * scale } 

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
                    .offset(x: digitDrawingWidth / 2 + dotSize / 2 + (2 * scale), y: digitDrawingHeight / 2 - dotSize / 2)
            }
        }
        .frame(width: digitDrawingWidth + dotSize + (4*scale), height: digitDrawingHeight) 
        // .drawingGroup() 
    }

    private func isSegmentActive(_ mask: UInt8) -> Bool {
        (digitPattern & mask) != 0
    }

    private enum Segment {
        case A, B, C, D, E, F, G
    }

    private func segmentPath(for segment: Segment) -> Path {
        // var path = Path() 
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
            return Path(CGRect(x: -segmentLengthHorizontal/2 + st/2, y: topY - st/2, width: segmentLengthHorizontal - st, height: st))
        case .G: 
            return Path(CGRect(x: -segmentLengthHorizontal/2 + st/2, y: midY - st/2, width: segmentLengthHorizontal - st, height: st))
        case .D: 
            return Path(CGRect(x: -segmentLengthHorizontal/2 + st/2, y: botY - st/2, width: segmentLengthHorizontal - st, height: st))
        
        case .F: 
            return Path(CGRect(x: leftX - st/2, y: topY + st/2, width: st, height: segmentLengthVertical - st))
        case .B: 
            return Path(CGRect(x: rightX - st/2, y: topY + st/2, width: st, height: segmentLengthVertical - st))

        case .E: 
            return Path(CGRect(x: leftX - st/2, y: midY + st/2, width: st, height: segmentLengthVertical - st))
        case .C: 
            return Path(CGRect(x: rightX - st/2, y: midY + st/2, width: st, height: segmentLengthVertical - st))
        }
    }
}

struct SegmentShape: Shape {
    let pathDefinition: Path

    func path(in rect: CGRect) -> Path {
        let offsetX = rect.midX
        let offsetY = rect.midY
        return pathDefinition.applying(CGAffineTransform(translationX: offsetX, y: offsetY))
    }
}

struct SevenSegmentDigitView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
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
