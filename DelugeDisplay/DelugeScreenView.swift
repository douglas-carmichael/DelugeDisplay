import SwiftUI
import OSLog
import UniformTypeIdentifiers

struct DelugeScreenView: View {
    @EnvironmentObject var midiManager: MIDIManager

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
        
        switch midiManager.displayColorMode {
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
        
        let currentFrameBuffer = midiManager.frameBuffer
        guard !currentFrameBuffer.isEmpty, currentFrameBuffer.count == screenWidth * blocksHigh else {
            logger.info("Frame buffer is invalid or empty for OLED image creation.")
            return context.makeImage() // Return background
        }

        for blk in 0..<blocksHigh {
            for row in 0..<8 {
                let mask = UInt8(1 << row)
                for col in 0..<screenWidth {
                    let byteIndex = blk * screenWidth + col
                    let byte = flipByte(currentFrameBuffer[byteIndex])
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

    private static func createCGImageForScreenshot(
        frameBuffer: [UInt8],
        colorMode: DelugeDisplayColorMode,
        screenWidth: Int,
        screenHeight: Int,
        blocksHigh: Int,
        scale: Int,
        logger: Logger
    ) -> CGImage? {
        let scaledWidth = screenWidth * scale
        let scaledHeight = screenHeight * scale
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        guard let context = CGContext(data: nil,
                              width: scaledWidth,
                              height: scaledHeight,
                              bitsPerComponent: 8,
                              bytesPerRow: scaledWidth * 4,
                              space: colorSpace,
                              bitmapInfo: bitmapInfo.rawValue) else {
            logger.error("Screenshot: Failed to create CGContext")
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
        
        guard !frameBuffer.isEmpty, frameBuffer.count == screenWidth * blocksHigh else {
            logger.info("Screenshot: Frame buffer invalid or empty.")
            return context.makeImage() // Return background
        }

        for blk in 0..<blocksHigh {
            for row in 0..<8 {
                let mask = UInt8(1 << row)
                for col in 0..<screenWidth {
                    let byteIndex = blk * screenWidth + col
                    var flippedLocal: UInt8 = 0
                    for i in 0..<8 { if (frameBuffer[byteIndex] & (1 << i)) != 0 { flippedLocal |= (1 << (7 - i)) } }
                    let byte = flippedLocal // Use the locally flipped byte

                    let pixelOn = (byte & mask) != 0
                    if pixelOn {
                        let y = scaledHeight - (blk * 8 + (7 - row)) * scale - scale
                        context.fill(CGRect(x: col * scale, y: y, width: scale, height: scale))
                    }
                }
            }
        }
        return context.makeImage()
    }
    
    static func saveScreenshotFromCurrentDisplay(midiManager: MIDIManager) {
        guard midiManager.displayMode == .oled else {
            let staticLogger = Logger(subsystem: "com.delugedisplay", category: "DelugeScreenView.Static")
            staticLogger.info("Screenshot for 7-segment display not implemented yet.")
            return
        }

        let localScreenWidth = 128
        let localScreenHeight = 48
        let localBlocksHigh = 6
        let localLogger = Logger(subsystem: "com.delugedisplay", category: "DelugeScreenView.StaticSave")


        guard let image = createCGImageForScreenshot(
            frameBuffer: midiManager.frameBuffer,
            colorMode: midiManager.displayColorMode,
            screenWidth: localScreenWidth,
            screenHeight: localScreenHeight,
            blocksHigh: localBlocksHigh,
            scale: 4,
            logger: localLogger
        ) else {
            localLogger.error("Failed to create image for screenshot")
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "DelugeDisplay_OLED_\(timestamp).png"
        
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = [UTType.png]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    localLogger.error("Failed to create image destination")
                    return
                }
                let properties = [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144]
                CGImageDestinationAddImage(destination, image, properties as CFDictionary)
                if !CGImageDestinationFinalize(destination) {
                    localLogger.error("Failed to save screenshot")
                }
            }
        }
    }
        
    func saveScreenshot() {
        guard midiManager.displayMode == .oled else {
            logger.info("Screenshot currently only supported for OLED display mode.")
            return
        }
        guard let image = createImage(width: screenWidth, height: screenHeight, scale: 4) else {
            logger.error("Failed to create image for screenshot")
            return
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "DelugeDisplay_OLED_\(timestamp).png"
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
                let properties = [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144]
                CGImageDestinationAddImage(destination, image, properties as CFDictionary)
                if !CGImageDestinationFinalize(destination) {
                    logger.error("Failed to save screenshot")
                }
            }
        }
    }
    
    var body: some View {
        if midiManager.displayMode == .oled {
            GeometryReader { geometry in
                Canvas { context, size in
                    guard !midiManager.frameBuffer.isEmpty, midiManager.frameBuffer.count == screenWidth * blocksHigh else {
                        context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .color(midiManager.displayColorMode == .normal ? .black : .white)
                        )
                        return
                    }
                    if let image = createImage(width: screenWidth, height: screenHeight) {
                        let resolvedImage = Image(image, scale: 1.0, label: Text("OLED Display"))
                            .interpolation(midiManager.smoothingEnabled ? midiManager.smoothingQuality : .none)
                        context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .color(midiManager.displayColorMode == .normal ? .black : .white)
                        )
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
                        context.draw(resolvedImage, in: CGRect(x: x, y: y, width: drawWidth, height: drawHeight))
                    } else {
                         context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .color(.gray)
                        )
                        logger.error("Failed to create CGImage for OLED display in Canvas.")
                    }
                }
            }
            .frame(
                idealWidth: CGFloat(screenWidth) * minimumScale,
                idealHeight: CGFloat(screenHeight) * minimumScale
            )
            .aspectRatio(CGFloat(screenWidth) / CGFloat(screenHeight), contentMode: .fit)
            .background(midiManager.displayColorMode == .normal ? Color.black : Color.white)
            .edgesIgnoringSafeArea(.all)
        } else { // Assumed .sevenSegment
            GeometryReader { geometry in
                SevenSegmentDisplayView(availableSize: geometry.size)
                    .background(Color.black)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .edgesIgnoringSafeArea(.all)
        }
    }
}

/*
 struct DelugeScreenView_Previews: PreviewProvider {
    static var previews: some View {
        // ... preview setup ...
    }
 }
*/
