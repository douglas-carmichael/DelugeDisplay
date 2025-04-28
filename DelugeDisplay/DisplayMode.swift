import Foundation

enum DelugeDisplayMode: String {
    case oled = "OLED"
    case sevenSegment = "7-Segment"
}

enum DelugeDisplayColorMode: String, CaseIterable {
    case normal = "White on Black"
    case inverted = "Black on White"
}
