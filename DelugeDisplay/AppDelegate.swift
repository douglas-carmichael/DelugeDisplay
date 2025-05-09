#if os(macOS)

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var midiManager: MIDIManager? 
    let minWidth: CGFloat = 512  // 128 * 4 in points
    let minHeight: CGFloat = 192  // 48 * 4 in points
    var aboutWindow: NSWindow?
    var initialWindowY: CGFloat?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Remove standard menu items
        if let mainMenu = NSApplication.shared.mainMenu {
            if let fileMenu = mainMenu.item(withTitle: "File")?.submenu {
                let closeIndex = fileMenu.indexOfItem(withTitle: "Close")
                if closeIndex >= 0 {
                    fileMenu.removeItem(at: closeIndex)
                }
            }
        }

        
        if let window = NSApplication.shared.windows.first {
            window.delegate = self
            window.contentView?.layerContentsRedrawPolicy = .onSetNeedsDisplay
            
            // Disable window collection behavior
            window.collectionBehavior = []
            
            // Set minimum size in points
            let backingScaleFactor = window.screen?.backingScaleFactor ?? 1.0
            window.minSize = NSSize(
                width: minWidth / backingScaleFactor,
                height: minHeight / backingScaleFactor
            )
        }
        
    }
    
    public func resetToMinimumSize(window: NSWindow) {
        guard let screen = window.screen else { return }
        let backingScaleFactor = screen.backingScaleFactor
        let minWindowWidth = minWidth / backingScaleFactor
        let minWindowHeight = minHeight / backingScaleFactor
        
        // Get current size
        let currentSize = window.frame.size
        
        // If already at minimum size, do nothing
        if abs(currentSize.width - minWindowWidth) < 1.0 &&
           abs(currentSize.height - minWindowHeight) < 1.0 {
            return
        }
        
        // Set new size while keeping position
        window.setContentSize(NSSize(width: minWindowWidth, height: minWindowHeight))
    }
    
    public func resizeWindow(scale: CGFloat, window: NSWindow) {
        guard let screen = window.screen else { return }
        let backingScaleFactor = screen.backingScaleFactor
        let minWindowWidth = minWidth / backingScaleFactor
        let minWindowHeight = minHeight / backingScaleFactor
        
        // If at minimum size and trying to shrink, do nothing
        if window.frame.size.width <= minWindowWidth && scale < 1.0 {
            return
        }
        
        // Calculate new size
        var newSize = NSSize(
            width: window.frame.size.width * scale,
            height: window.frame.size.height * scale
        )
        
        // Enforce minimum size
        if newSize.width < minWindowWidth {
            newSize = NSSize(width: minWindowWidth, height: minWindowHeight)
        }
        
        // Enforce maximum size
        let maxWidth = screen.visibleFrame.width * 0.95
        let maxHeight = screen.visibleFrame.height * 0.95
        
        if newSize.width > maxWidth {
            let scale = maxWidth / newSize.width
            newSize.width = maxWidth
            newSize.height *= scale
        }
        
        if newSize.height > maxHeight {
            let scale = maxHeight / newSize.height
            newSize.height = maxHeight
            newSize.width *= scale
        }
        
        // Set size directly
        window.setContentSize(newSize)
    }
    
    private func hasMinimumSize(_ window: NSWindow) -> Bool {
        guard let screen = window.screen else { return false }
        let backingScaleFactor = screen.backingScaleFactor
        let minWindowWidth = minWidth / backingScaleFactor
        let minWindowHeight = minHeight / backingScaleFactor
        
        // Only check the size, not the position
        return abs(window.frame.size.width - minWindowWidth) < 1.0 &&
               abs(window.frame.size.height - minWindowHeight) < 1.0
    }
    
    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            // Update stored Y position when user moves the window
            initialWindowY = window.frame.origin.y
        }
    }
    
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let backingScaleFactor = sender.screen?.backingScaleFactor ?? 1.0
        let minWindowWidth = minWidth / backingScaleFactor
        let minWindowHeight = minHeight / backingScaleFactor
        
        // Enforce minimum size
        let newWidth = max(frameSize.width, minWindowWidth)
        
        // Maintain aspect ratio
        let aspectRatio: CGFloat = 8/3 // 512/192
        let newHeight = newWidth / aspectRatio
        
        // Double-check height meets minimum
        if newHeight < minWindowHeight {
            return NSSize(width: minWindowWidth, height: minWindowHeight)
        }
        
        return NSSize(width: newWidth, height: newHeight)
    }
    
    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            window.contentView?.setNeedsDisplay(window.contentView?.bounds ?? .zero)
            
            // Force minimum size if needed
            let backingScaleFactor = window.screen?.backingScaleFactor ?? 1.0
            let minWindowWidth = minWidth / backingScaleFactor
            let minWindowHeight = minHeight / backingScaleFactor
            
            if window.frame.width < minWindowWidth || window.frame.height < minWindowHeight {
                window.setFrame(NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y,
                    width: minWindowWidth,
                    height: minWindowHeight
                ), display: true)
            }
        }
    }
    
    func windowDidChangeScreen(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            let backingScaleFactor = window.screen?.backingScaleFactor ?? 1.0
            window.minSize = NSSize(
                width: minWidth / backingScaleFactor,
                height: minHeight / backingScaleFactor
            )
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        midiManager?.disconnect()
    }
    
    @objc func showAboutWindow() {
        if aboutWindow == nil {
            let aboutView = AboutView()
            let hostingController = NSHostingController(rootView: aboutView)
            
            aboutWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            
            aboutWindow?.contentViewController = hostingController
            aboutWindow?.title = "About DelugeDisplay"
            aboutWindow?.standardWindowButton(.miniaturizeButton)?.isHidden = true
            aboutWindow?.standardWindowButton(.zoomButton)?.isHidden = true
            aboutWindow?.center()
            aboutWindow?.isReleasedWhenClosed = false
            aboutWindow?.backgroundColor = .windowBackgroundColor
        }
        
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#endif
