import SwiftUI
import OSLog

struct DelugeScreenView: View {
    let frameBuffer: [UInt8]
    let smoothingEnabled: Bool
    let smoothingQuality: Image.Interpolation
    
    private let screenWidth = 128
    private let screenHeight = 48
    private let blocksHigh = 6
    private let minimumScale: CGFloat = 2.0
    
    private let logger = Logger(subsystem: "com.delugedisplay", category: "DelugeScreenView")
    
    private func flipByte(_ byte: UInt8) -> UInt8 {
        var flipped: UInt8 = 0
        for i in 0..<8 {
            if (byte & (1 << i)) != 0 {
                flipped |= (1 << (7 - i))
            }
        }
        return flipped
    }
    
    private func createImage(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        guard let context = CGContext(data: nil,
                              width: width,
                              height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: width * 4,
                              space: colorSpace,
                              bitmapInfo: bitmapInfo.rawValue) else {
            logger.error("Failed to create CGContext")
            return nil
        }
        
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
        
        for blk in 0..<blocksHigh {
            for row in 0..<8 {
                let mask = UInt8(1 << row)
                for col in 0..<screenWidth {
                    let byteIndex = blk * screenWidth + col
                    guard byteIndex < frameBuffer.count else {
                        logger.error("Frame buffer index out of bounds: \(byteIndex)")
                        continue 
                    }
                    
                    let byte = flipByte(frameBuffer[byteIndex])
                    let pixelOn = (byte & mask) != 0
                    
                    if pixelOn {
                        let y = height - (blk * 8 + (7 - row)) - 1
                        context.fill(CGRect(
                            x: col,
                            y: y,
                            width: 1,
                            height: 1
                        ))
                    }
                }
            }
        }
        
        return context.makeImage()
    }
    
    var body: some View {
        GeometryReader { geometry in
            let scale = max(
                minimumScale,
                floor(min(
                    geometry.size.width / CGFloat(screenWidth),
                    geometry.size.height / CGFloat(screenHeight)
                ))
            )
            
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                
                guard frameBuffer.count == screenWidth * blocksHigh else { return }
                
                if let image = createImage(width: screenWidth, height: screenHeight) {
                    let resolvedImage = Image(image, scale: 1.0, label: Text(""))
                        .interpolation(smoothingEnabled ? smoothingQuality : .none)
                    
                    let scaledWidth = CGFloat(screenWidth) * scale
                    let scaledHeight = CGFloat(screenHeight) * scale
                    let x = (size.width - scaledWidth) / 2
                    let y = (size.height - scaledHeight) / 2
                    
                    context.draw(resolvedImage, in: CGRect(
                        x: x,
                        y: y,
                        width: scaledWidth,
                        height: scaledHeight
                    ))
                }
            }
            .background(Color.black)
        }
        .aspectRatio(CGFloat(screenWidth) / CGFloat(screenHeight), contentMode: .fit)
        .frame(minWidth: CGFloat(screenWidth) * minimumScale,
               minHeight: CGFloat(screenHeight) * minimumScale)
    }
}
