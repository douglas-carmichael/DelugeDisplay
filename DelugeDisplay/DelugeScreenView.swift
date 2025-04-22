import SwiftUI

struct DelugeScreenView: View {
    let frameBuffer: [UInt8]
    private let screenWidth = 128
    private let screenHeight = 48
    private let blocksHigh = 6
    
    private func flipByte(_ byte: UInt8) -> UInt8 {
        var flipped: UInt8 = 0
        for i in 0..<8 {
            if (byte & (1 << i)) != 0 {
                flipped |= (1 << (7 - i))
            }
        }
        return flipped
    }
    
    var body: some View {
        Canvas { context, size in
            let pixelWidth = size.width / CGFloat(screenWidth)
            let pixelHeight = size.height / CGFloat(screenHeight)
            
            // Clear background
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            
            // Validate frame data
            guard frameBuffer.count == screenWidth * blocksHigh else { return }
            
            // Process blocks in normal order (top to bottom)
            for blk in 0..<blocksHigh {
                for row in 0..<8 {
                    let mask = UInt8(1 << row)
                    for col in 0..<screenWidth {
                        // Calculate byte index
                        let byteIndex = blk * screenWidth + col
                        guard byteIndex < frameBuffer.count else { continue }
                        
                        // Flip bits in each byte
                        let byte = flipByte(frameBuffer[byteIndex])
                        let pixelOn = (byte & mask) != 0
                        
                        if pixelOn {
                            let rect = CGRect(
                                x: CGFloat(col) * pixelWidth,
                                y: CGFloat(blk * 8 + (7 - row)) * pixelHeight,
                                width: pixelWidth,
                                height: pixelHeight
                            )
                            context.fill(Path(rect), with: .color(.white))
                        }
                    }
                }
            }
        }
        .background(Color.black)
        .aspectRatio(CGFloat(screenWidth) / CGFloat(screenHeight), contentMode: .fit)
    }
}
