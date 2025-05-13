import Foundation

enum DelugeDisplayMode: String {
    case oled = "OLED"
    case sevenSegment = "7-Segment"
}

enum DelugeDisplayColorMode: String, CaseIterable {
    case normal = "Default"
    case inverted = "Black on White"
    case matrix = "Green on Black"
}
