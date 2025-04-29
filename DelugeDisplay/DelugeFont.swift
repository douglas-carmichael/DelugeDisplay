import SwiftUI

struct DelugeFont {
    // 5x7 pixel grid for each character
    static let characterWidth = 5
    static let characterHeight = 7
    static let spacing = 4 // Space between characters
    
    // Bitmap definitions for characters
    static let characters: [String: [[Bool]]] = [
        "A": [
            [false, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, true, true, true, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true]
        ],
        "B": [
            [true, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, true, true, true, false]
        ],
        "C": [
            [false, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, false, false, false, true],
            [false, true, true, true, false]
        ],
        "D": [
            [true, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, true, true, true, false]
        ],
        "E": [
            [true, true, true, true, true],
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, true, true, true, false],
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, true, true, true, true]
        ],
        "F": [
            [true, true, true, true, true],
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, true, true, true, false],
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, false, false, false, false]
        ],
        "G": [
            [false, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, false],
            [true, false, true, true, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [false, true, true, true, false]
        ],
        "H": [
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, true, true, true, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true]
        ],
        "I": [
            [true, true, true, true, true],
            [false, false, true, false, false],
            [false, false, true, false, false],
            [false, false, true, false, false],
            [false, false, true, false, false],
            [false, false, true, false, false],
            [true, true, true, true, true]
        ],
        "J": [
            [false, false, true, true, true],
            [false, false, false, true, false],
            [false, false, false, true, false],
            [false, false, false, true, false],
            [true, false, false, true, false],
            [true, false, false, true, false],
            [false, true, true, false, false]
        ],
        "K": [
            [true, false, false, false, true],
            [true, false, false, true, false],
            [true, false, true, false, false],
            [true, true, false, false, false],
            [true, false, true, false, false],
            [true, false, false, true, false],
            [true, false, false, false, true]
        ],
        "L": [
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, true, true, true, true]
        ],
        "M": [
            [true, false, false, false, true],
            [true, true, false, true, true],
            [true, false, true, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true]
        ],
        "N": [
            [true, false, false, false, true],
            [true, true, false, false, true],
            [true, false, true, false, true],
            [true, false, false, true, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true]
        ],
        "O": [
            [false, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [false, true, true, true, false]
        ],
        "P": [
            [true, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, true, true, true, false],
            [true, false, false, false, false],
            [true, false, false, false, false],
            [true, false, false, false, false]
        ],
        "Q": [
            [false, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, true, false, true],
            [true, false, false, true, false],
            [false, true, true, false, true]
        ],
        "R": [
            [true, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, true, true, true, false],
            [true, false, true, false, false],
            [true, false, false, true, false],
            [true, false, false, false, true]
        ],
        "S": [
            [false, true, true, true, false],
            [true, false, false, false, true],
            [true, false, false, false, false],
            [false, true, true, true, false],
            [false, false, false, false, true],
            [true, false, false, false, true],
            [false, true, true, true, false]
        ],
        "T": [
            [true, true, true, true, true],
            [false, false, true, false, false],
            [false, false, true, false, false],
            [false, false, true, false, false],
            [false, false, true, false, false],
            [false, false, true, false, false],
            [false, false, true, false, false]
        ],
        "U": [
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [false, true, true, true, false]
        ],
        "V": [
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [false, true, false, true, false],
            [false, false, true, false, false]
        ],
        "W": [
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, false, false, true],
            [true, false, true, false, true],
            [true, false, true, false, true],
            [true, true, false, true, true],
            [true, false, false, false, true]
        ],
        "X": [
            [true, false, false, false, true],
            [true, false, false, false, true],
            [false, true, false, true, false],
            [false, false, true, false, false],
            [false, true, false, true, false],
            [true, false, false, false, true],
            [true, false, false, false, true]
        ],
        "Y": [
            [true, false, false, false, true],
            [true, false, false, false, true],
            [false, true, false, true, false],
            [false, false, true, false, false],
            [false, false, true, false, false],
            [false, false, true, false, false],
            [false, false, true, false, false]
        ],
        "Z": [
            [true, true, true, true, true],
            [false, false, false, false, true],
            [false, false, false, true, false],
            [false, false, true, false, false],
            [false, true, false, false, false],
            [true, false, false, false, false],
            [true, true, true, true, true]
        ],
        " ": [
            [false, false, false, false, false],
            [false, false, false, false, false],
            [false, false, false, false, false],
            [false, false, false, false, false],
            [false, false, false, false, false],
            [false, false, false, false, false],
            [false, false, false, false, false]
        ]
    ]
    
    static func renderText(_ text: String, color: Color = .white) -> some View {
        HStack(spacing: CGFloat(spacing)) {
            ForEach(Array(text.uppercased()), id: \.self) { char in
                if let bitmap = characters[String(char)] {
                    characterView(bitmap: bitmap, color: color)
                }
            }
        }
    }
    
    private static func characterView(bitmap: [[Bool]], color: Color) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<bitmap.count, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<bitmap[row].count, id: \.self) { col in
                        Rectangle()
                            .fill(bitmap[row][col] ? color : .clear)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
    }
}
