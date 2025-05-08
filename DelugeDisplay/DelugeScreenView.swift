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
            #if DEBUG
            logger.error("Failed to create CGContext")
            #endif
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
            #if DEBUG
            logger.info("Frame buffer is invalid or empty for OLED image creation.")
            #endif
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
            #if DEBUG
            logger.error("Screenshot: Failed to create CGContext")
            #endif
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
            #if DEBUG
            logger.info("Screenshot: Frame buffer invalid or empty.")
            #endif
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
        let localLogger = Logger(subsystem: "com.delugedisplay", category: "DelugeScreenView.StaticSave")
        var image: CGImage? = nil
        var filenamePrefix = "DelugeDisplay"

        if midiManager.displayMode == .oled {
            let localScreenWidth = 128
            let localScreenHeight = 48
            let localBlocksHigh = 6
            
            image = createCGImageForScreenshot(
                frameBuffer: midiManager.frameBuffer,
                colorMode: midiManager.displayColorMode,
                screenWidth: localScreenWidth,
                screenHeight: localScreenHeight,
                blocksHigh: localBlocksHigh,
                scale: 4, // Scale for OLED screenshot
                logger: localLogger
            )
            filenamePrefix = "DelugeDisplay_OLED"
            
        } else if midiManager.displayMode == .sevenSegment {
            #if DEBUG
            localLogger.info("Attempting to save screenshot for 7-Segment display.")
            #endif
            
            let screenshotSize = CGSize(width: 400, height: 150)
            
            let sevenSegmentView = SevenSegmentDisplayView(availableSize: screenshotSize)
                .environmentObject(midiManager)
                .frame(width: screenshotSize.width, height: screenshotSize.height)
            let renderer = ImageRenderer(content: sevenSegmentView)
            renderer.scale = 2.0
            
            image = renderer.cgImage
            filenamePrefix = "DelugeDisplay_7Segment"

        } else {
            #if DEBUG
            localLogger.warning("Screenshot not supported for current display mode: \(midiManager.displayMode.rawValue)")
            #endif
            return
        }

        guard let finalImage = image else {
            #if DEBUG
            localLogger.error("Failed to create image for screenshot for mode: \(midiManager.displayMode.rawValue)")
            #endif
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "\(filenamePrefix)_\(timestamp).png"
        
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = [UTType.png]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    #if DEBUG
                    localLogger.error("Failed to create image destination")
                    #endif
                    return
                }
                let properties = [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144]
                CGImageDestinationAddImage(destination, finalImage, properties as CFDictionary)
                if !CGImageDestinationFinalize(destination) {
                    #if DEBUG
                    localLogger.error("Failed to save screenshot")
                    #endif
                }
            }
        }
    }
        
    func saveScreenshot() {
        guard midiManager.displayMode == .oled else {
            #if DEBUG
            logger.info("Screenshot currently only supported for OLED display mode.")
            #endif
            return
        }
        guard let image = createImage(width: screenWidth, height: screenHeight, scale: 4) else {
            #if DEBUG
            logger.error("Failed to create image for screenshot")
            #endif
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
                    #if DEBUG
                    logger.error("Failed to create image destination")
                    #endif
                    return
                }
                let properties = [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144]
                CGImageDestinationAddImage(destination, image, properties as CFDictionary)
                if !CGImageDestinationFinalize(destination) {
                    #if DEBUG
                    logger.error("Failed to save screenshot")
                    #endif
                }
            }
        }
    }
    
    private struct OLEDViewContent: View {
        @EnvironmentObject var midiManager: MIDIManager
        let screenWidth: Int
        let screenHeight: Int
        let blocksHigh: Int
        let minimumScale: CGFloat
        var parent: DelugeScreenView

        var body: some View {
            guard midiManager.displayMode == .oled else {
                return AnyView(Color.clear)
            }

            return AnyView(
                GeometryReader { geometry in
                    let availableAspect = geometry.size.width / geometry.size.height
                    let imageAspect = CGFloat(screenWidth) / CGFloat(screenHeight)
                    
                    let (drawWidth, drawHeight): (CGFloat, CGFloat) = {
                        var calculatedWidth: CGFloat
                        var calculatedHeight: CGFloat
                        if availableAspect > imageAspect {
                            calculatedHeight = geometry.size.height
                            calculatedWidth = calculatedHeight * imageAspect
                        } else {
                            calculatedWidth = geometry.size.width
                            calculatedHeight = calculatedWidth / imageAspect
                        }
                        return (calculatedWidth, calculatedHeight)
                    }()
                    
                    let effectiveOledScale = screenWidth > 0 ? drawWidth / CGFloat(screenWidth) : 1.0

                    let oledBlurRadius: CGFloat = {
                        if !midiManager.smoothingEnabled { return 0 }
                        let baseLow: CGFloat = 0.1, baseMedium: CGFloat = 0.3, baseHigh: CGFloat = 0.6
                        var tempRadius: CGFloat = 0
                        switch midiManager.smoothingQuality {
                        case .low: tempRadius = baseLow
                        case .medium: tempRadius = baseMedium
                        case .high: tempRadius = baseHigh
                        default: tempRadius = baseMedium
                        }
                        return tempRadius * effectiveOledScale
                    }()

                    Canvas { context, size in
                        guard !midiManager.frameBuffer.isEmpty, midiManager.frameBuffer.count == screenWidth * blocksHigh else {
                            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(midiManager.displayColorMode == .normal ? .black : .white))
                            return
                        }
                        if let cgImage = parent.createImage(width: screenWidth, height: screenHeight) {
                            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(midiManager.displayColorMode == .normal ? .black : .white))
                            context.draw(Image(cgImage, scale: 1.0, label: Text("OLED Display")).interpolation(.none), in: CGRect(origin: .zero, size: size))
                        } else {
                             context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.gray))
                             #if DEBUG
                             // parent.logger.error(...) // logger is also on parent
                             #endif
                        }
                    }
                    .blur(radius: oledBlurRadius)
                    .frame(width: drawWidth, height: drawHeight)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                .frame(idealWidth: CGFloat(screenWidth) * minimumScale, idealHeight: CGFloat(screenHeight) * minimumScale)
                .aspectRatio(CGFloat(screenWidth) / CGFloat(screenHeight), contentMode: .fit)
                .background(midiManager.displayColorMode == .normal ? Color.black : Color.white)
                .edgesIgnoringSafeArea(.all)
            )
        }
    }
    
    private struct SevenSegmentViewContent: View {
        @EnvironmentObject var midiManager: MIDIManager 

        var body: some View {
            if midiManager.displayMode == .sevenSegment {
                GeometryReader { geometry in
                    SevenSegmentDisplayView(availableSize: geometry.size)
                        .id("\(midiManager.sevenSegmentDigits)-\(midiManager.sevenSegmentDots)")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .edgesIgnoringSafeArea(.all)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .edgesIgnoringSafeArea(.all)
            }
        }
    }
    
    @ViewBuilder
    var body: some View {
        Group {
            switch midiManager.displayMode {
            case .oled:
                OLEDViewContent(screenWidth: screenWidth, screenHeight: screenHeight, blocksHigh: blocksHigh, minimumScale: minimumScale, parent: self)
                    .zIndex(1) 
            case .sevenSegment:
                SevenSegmentViewContent()
                    .zIndex(0)
            }
        }
        .id(midiManager.displayMode)
        .animation(nil, value: midiManager.displayMode)
    }
}

/*
 struct DelugeScreenView_Previews: PreviewProvider {
    static var previews: some View {
        // ... preview setup ...
    }
 }
*/
