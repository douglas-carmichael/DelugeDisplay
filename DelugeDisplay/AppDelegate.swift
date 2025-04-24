import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    @ObservedObject var midiManager = MIDIManager()
    let minWidth: CGFloat = 512  // 128 * 4 in points
    let minHeight: CGFloat = 192  // 48 * 4 in points
    
    func applicationDidFinishLaunching(_ notification: Notification) {
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
    
    // Handle manual resizing while maintaining aspect ratio and minimum size
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
        midiManager.disconnect()
    }
}
