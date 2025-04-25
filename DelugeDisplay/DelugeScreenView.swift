import SwiftUI
import OSLog

struct DelugeScreenView: View {
    let frameBuffer: [UInt8]
    let smoothingEnabled: Bool
    let smoothingQuality: Image.Interpolation
    
    private let screenWidth = 128
    private let screenHeight = 48
    private let blocksHigh = 6
    private let minimumScale: CGFloat = 3.5  // Increased scale
    
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
            Canvas { context, size in
                guard frameBuffer.count == screenWidth * blocksHigh else { return }
                
                if let image = createImage(width: screenWidth, height: screenHeight) {
                    let resolvedImage = Image(image, scale: 1.0, label: Text(""))
                        .interpolation(smoothingEnabled ? smoothingQuality : .none)
                    
                    // Fill the entire canvas with black first
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                    
                    // Calculate dimensions to maintain aspect ratio while filling available space
                    let availableAspect = size.width / size.height
                    let imageAspect = CGFloat(screenWidth) / CGFloat(screenHeight)
                    
                    let drawWidth: CGFloat
                    let drawHeight: CGFloat
                    
                    if availableAspect > imageAspect {
                        drawHeight = size.height
                        drawWidth = drawHeight * imageAspect
                    } else {
                        drawWidth = size.width
                        drawHeight = drawWidth / imageAspect
                    }
                    
                    let x = (size.width - drawWidth) / 2
                    let y = (size.height - drawHeight) / 2
                    
                    context.draw(resolvedImage, in: CGRect(
                        x: x,
                        y: y,
                        width: drawWidth,
                        height: drawHeight
                    ))
                }
            }
        }
        .frame(
            idealWidth: CGFloat(screenWidth) * minimumScale,
            idealHeight: CGFloat(screenHeight) * minimumScale
        )
        .aspectRatio(CGFloat(screenWidth) / CGFloat(screenHeight), contentMode: .fit)
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
    }
}
