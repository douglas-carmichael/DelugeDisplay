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
            logger.error("Failed to create CGContext for createImage")
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
        
        guard !currentFrameBuffer.isEmpty, currentFrameBuffer.count == self.screenWidth * self.blocksHigh else {
            #if DEBUG
            logger.info("Frame buffer is invalid or empty for createImage.")
            #endif
            return context.makeImage()
        }

        let isPixelGridMode = midiManager.oledPixelGridModeEnabled
        let pixelBlockSize = CGFloat(scale)

        var inset: CGFloat = 0.0
        if isPixelGridMode {
            let targetLitProportion: CGFloat = 0.78
            let minPixelGapInOutputImage: CGFloat = 1.0 // Gap at least 1px in output

            let desiredLitDim = pixelBlockSize * targetLitProportion
            let initialGap = pixelBlockSize - desiredLitDim
            let finalGap = max(minPixelGapInOutputImage, initialGap)
            inset = max(0, finalGap / 2.0)
        }

        for blk in 0..<self.blocksHigh {
            for rowInBlock in 0..<8 {
                let mask = UInt8(1 << rowInBlock)
                for col in 0..<self.screenWidth {
                    
                    let byteIndex = blk * self.screenWidth + col
                    
                    guard byteIndex >= 0 && byteIndex < currentFrameBuffer.count else { continue }
                    let sourceByte = currentFrameBuffer[byteIndex]
                    
                    let pixelOn = (sourceByte & mask) != 0
                    
                    if pixelOn {
                        let cgX = CGFloat(col * scale)
                        let cgY = CGFloat((blk * 8 + rowInBlock) * scale)

                        let rectX = cgX + inset
                        let rectY = cgY + inset
                        let rectSide = pixelBlockSize - (2 * inset)

                        if rectSide > 0 {
                             context.fill(CGRect(x: rectX, y: rectY, width: rectSide, height: rectSide))
                        } else if !isPixelGridMode {
                             context.fill(CGRect(x: cgX, y: cgY, width: pixelBlockSize, height: pixelBlockSize))
                        }
                    }
                }
            }
        }
        return context.makeImage()
    }

    private static func createCGImageForScreenshot(
        frameBuffer: [UInt8],
        colorMode: DelugeDisplayColorMode,
        isPixelGridMode: Bool,
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
            logger.info("Screenshot: Frame buffer invalid or empty. Expected \(screenWidth * blocksHigh), got \(frameBuffer.count)")
            #endif
            return context.makeImage()
        }

        let pixelBlockSize = CGFloat(scale)

        var inset: CGFloat = 0.0
        if isPixelGridMode {
            let targetLitProportion: CGFloat = 0.78
            let minPixelGapInOutputImage: CGFloat = 1.0 // Gap at least 1px in output

            let desiredLitDim = pixelBlockSize * targetLitProportion
            let initialGap = pixelBlockSize - desiredLitDim
            let finalGap = max(minPixelGapInOutputImage, initialGap)
            inset = max(0, finalGap / 2.0)
        }

        for blk in 0..<blocksHigh {
            for rowInBlock in 0..<8 {
                let mask = UInt8(1 << rowInBlock)
                for col in 0..<screenWidth {
                    
                    let byteIndex = blk * screenWidth + col
                    
                    guard byteIndex >= 0 && byteIndex < frameBuffer.count else { continue }
                    let sourceByte = frameBuffer[byteIndex]
                    
                    let pixelOn = (sourceByte & mask) != 0
                    if pixelOn {
                        let cgX = CGFloat(col * scale)
                        let cgY = CGFloat((blk * 8 + rowInBlock) * scale)

                        let rectX = cgX + inset
                        let rectY = cgY + inset
                        let rectSide = pixelBlockSize - (2 * inset)

                        if rectSide > 0 {
                            context.fill(CGRect(x: rectX, y: rectY, width: rectSide, height: rectSide))
                        } else if !isPixelGridMode {
                            context.fill(CGRect(x: cgX, y: cgY, width: pixelBlockSize, height: pixelBlockSize))
                        }
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
                isPixelGridMode: midiManager.oledPixelGridModeEnabled,
                screenWidth: localScreenWidth,
                screenHeight: localScreenHeight,
                blocksHigh: localBlocksHigh,
                scale: 4,
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

        // flipByte function (not used in this rendering logic)
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
            GeometryReader { geometry in
                let drawWidth = geometry.size.width
                let drawHeight = geometry.size.height
                
                let canvasPixelWidth = screenWidth > 0 ? drawWidth / CGFloat(screenWidth) : 1.0
                let canvasPixelHeight = screenHeight > 0 ? drawHeight / CGFloat(screenHeight) : 1.0

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
                    return tempRadius * (min(canvasPixelWidth, canvasPixelHeight) / 2.0)
                }()

                // Use explicit name 'graphicsContext'
                Canvas { graphicsContext, size in
                    // Explicitly define SwiftUI Colors
                    let swiftBackgroundColor: SwiftUI.Color = Color(midiManager.displayColorMode == .normal ? .black : .white)
                    let swiftForegroundColor: SwiftUI.Color = Color(midiManager.displayColorMode == .normal ? .white : .black)

                    // Explicitly define Shading
                    let backgroundShading: GraphicsContext.Shading = GraphicsContext.Shading.color(swiftBackgroundColor)
                    let foregroundShading: GraphicsContext.Shading = GraphicsContext.Shading.color(swiftForegroundColor)

                    // Fill background
                    let backgroundRect: CGRect = CGRect(origin: .zero, size: size)
                    let backgroundPath: Path = Path(backgroundRect)
                    graphicsContext.fill(backgroundPath, with: backgroundShading)
                    
                    let currentFrameBuffer = midiManager.frameBuffer
                    guard !currentFrameBuffer.isEmpty, currentFrameBuffer.count == screenWidth * blocksHigh else {
                        return
                    }

                    let isPixelGridMode = midiManager.oledPixelGridModeEnabled
                    
                    var hInset: CGFloat = 0.0
                    var vInset: CGFloat = 0.0

                    // Inset calculation (using last working logic)
                    if isPixelGridMode {
                        let targetLitProportion: CGFloat = 0.78
                        let minPhysicalGapPoints: CGFloat = 0.70

                        let desiredLitW = canvasPixelWidth * targetLitProportion
                        let initialGapW = canvasPixelWidth - desiredLitW
                        let finalGapW = max(minPhysicalGapPoints, initialGapW)
                        hInset = max(0, finalGapW / 2.0)

                        let desiredLitH = canvasPixelHeight * targetLitProportion
                        let initialGapH = canvasPixelHeight - desiredLitH
                        let finalGapH = max(minPhysicalGapPoints, initialGapH)
                        vInset = max(0, finalGapH / 2.0)
                    }
                    
                    // Pixel drawing loop
                    for blk in 0..<blocksHigh {
                        for rowInBlock in 0..<8 {
                            let mask = UInt8(1 << rowInBlock)
                            for col in 0..<screenWidth {
                                let srcCol = col
                                let srcBlk = blk
                                let byteIndex = srcBlk * screenWidth + srcCol
                                
                                guard byteIndex >= 0 && byteIndex < currentFrameBuffer.count else { continue }
                                
                                let sourceByte = currentFrameBuffer[byteIndex]
                                let byteToRender = sourceByte
                                let pixelOn = (byteToRender & mask) != 0
                                
                                if pixelOn {
                                    let canvasX = CGFloat(col) * canvasPixelWidth
                                    let physicalRow = blk * 8 + rowInBlock
                                    let canvasY = CGFloat(physicalRow) * canvasPixelHeight

                                    let rectX = canvasX + hInset
                                    let rectY = canvasY + vInset
                                    let rectWidth = max(0, canvasPixelWidth - (2 * hInset))
                                    let rectHeight = max(0, canvasPixelHeight - (2 * vInset))

                                    if rectWidth > 0 && rectHeight > 0 {
                                        // Define CGRect, Path, and fill explicitly
                                        let pixelRect: CGRect = CGRect(x: rectX, y: rectY, width: rectWidth, height: rectHeight)
                                        let pixelPath: Path = Path(pixelRect)
                                        graphicsContext.fill(pixelPath, with: foregroundShading)
                                    }
                                }
                            } // End col loop
                        } // End rowInBlock loop
                    } // End blk loop
                } // End Canvas closure
                .blur(radius: oledBlurRadius)
                .frame(width: drawWidth, height: drawHeight)
            } // End GeometryReader
            .background(midiManager.displayColorMode == .normal ? Color.black : Color.white)
        } // End body
    } // End OLEDViewContent struct

    private struct SevenSegmentViewContent: View {
        @EnvironmentObject var midiManager: MIDIManager

        var body: some View {
            if midiManager.displayMode == .sevenSegment {
                GeometryReader { geometry in
                    SevenSegmentDisplayView(availableSize: geometry.size)
                        .environmentObject(midiManager)
                        .frame(width: geometry.size.width, height: geometry.size.height)
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
                OLEDViewContent(screenWidth: screenWidth, screenHeight: screenHeight, blocksHigh: blocksHigh)
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
