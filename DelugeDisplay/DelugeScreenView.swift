import SwiftUI
import OSLog
import UniformTypeIdentifiers

struct DelugeScreenView: View {
    let frameBuffer: [UInt8]
    let smoothingEnabled: Bool
    let smoothingQuality: Image.Interpolation
    let colorMode: DelugeDisplayColorMode
    
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
    
    private func createImage(width: Int, height: Int, scale: Int = 1) -> CGImage? {
        let scaledWidth = width * scale
        let scaledHeight = height * scale
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        guard let context = CGContext(data: nil,
                              width: scaledWidth,
                              height: scaledHeight,
                              bitsPerComponent: 8,
                              bytesPerRow: scaledWidth * 4,
                              space: colorSpace,
                              bitmapInfo: bitmapInfo.rawValue) else {
            logger.error("Failed to create CGContext")
            return nil
        }
        
        let backgroundColor: CGColor
        let foregroundColor: CGColor
        
        switch colorMode {
        case .normal:
            backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)
            foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1.0)
        case .inverted:
            backgroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1.0)
            foregroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        }
        
        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
        
        context.setFillColor(foregroundColor)
        
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
                        let y = scaledHeight - (blk * 8 + (7 - row)) * scale - scale
                        context.fill(CGRect(
                            x: col * scale,
                            y: y,
                            width: scale,
                            height: scale
                        ))
                    }
                }
            }
        }
        
        return context.makeImage()
    }
    
    static func saveScreenshotFromCurrentDisplay(frameBuffer: [UInt8], colorMode: DelugeDisplayColorMode) {
        let view = DelugeScreenView(
            frameBuffer: frameBuffer,
            smoothingEnabled: false,
            smoothingQuality: .none,
            colorMode: colorMode
        )
        
        // Create a 4x scaled image for the screenshot
        guard let image = view.createImage(width: view.screenWidth, height: view.screenHeight, scale: 4) else {
            view.logger.error("Failed to create image for screenshot")
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "DelugeDisplay_\(timestamp).png"
        
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = [UTType.png]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    view.logger.error("Failed to create image destination")
                    return
                }
                
                let properties = [kCGImagePropertyDPIWidth: 144,
                                kCGImagePropertyDPIHeight: 144]
                CGImageDestinationAddImage(destination, image, properties as CFDictionary)
                
                if !CGImageDestinationFinalize(destination) {
                    view.logger.error("Failed to save screenshot")
                }
            }
        }
    }
    
    func saveScreenshot() {
        guard let image = createImage(width: screenWidth, height: screenHeight) else {
            logger.error("Failed to create image for screenshot")
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "DelugeDisplay_\(timestamp).png"
        
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = [UTType.png]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    logger.error("Failed to create image destination")
                    return
                }
                
                let properties = [kCGImagePropertyDPIWidth: 144,
                                kCGImagePropertyDPIHeight: 144]
                CGImageDestinationAddImage(destination, image, properties as CFDictionary)
                
                if !CGImageDestinationFinalize(destination) {
                    logger.error("Failed to save screenshot")
                }
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard frameBuffer.count == screenWidth * blocksHigh else { return }
                
                if let image = createImage(width: screenWidth, height: screenHeight) {
                    let resolvedImage = Image(image, scale: 1.0, label: Text(""))
                        .interpolation(smoothingEnabled ? smoothingQuality : .none)
                    
                    // Fill the entire canvas with background color
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(colorMode == .normal ? .black : .white)
                    )
                    
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
        .background(colorMode == .normal ? Color.black : Color.white)
        .edgesIgnoringSafeArea(.all)
    }
}
