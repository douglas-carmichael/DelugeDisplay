import SwiftUI

struct DelugeScreenView: View {
    let frameBuffer: [UInt8]
    private let screenWidth = 128
    private let screenHeight = 48
    
    var body: some View {
        Canvas { context, size in
            // Calculate pixel size for scaling
            let pixelWidth = size.width / CGFloat(screenWidth)
            let pixelHeight = size.height / CGFloat(screenHeight)
            
            for blk in 0..<6 {
                for row in 0..<8 {
                    let mask = UInt8(1 << row)
                    for col in 0..<screenWidth {
                        let byte = frameBuffer[blk * screenWidth + col]
                        let pixelOn = (byte & mask) != 0
                        
                        if pixelOn {
                            let rect = CGRect(
                                x: CGFloat(col) * pixelWidth,
                                y: CGFloat(blk * 8 + row) * pixelHeight,
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
    }
}
