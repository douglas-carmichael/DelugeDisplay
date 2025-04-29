//
//  ContentView.swift
//  DelugeDisplay
//
//  Created by Douglas Carmichael on 4/21/25.
//

import SwiftUI
import CoreMIDI

struct ContentView: View {
    @EnvironmentObject var midiManager: MIDIManager
    
    func saveScreenshot() {
        guard midiManager.isConnected else { return }
        
        // Find the DelugeScreenView by looking through the view hierarchy
        guard let window = NSApplication.shared.windows.first,
              let contentView = window.contentView,
              let hostingView = contentView.subviews.first as? NSHostingView<ContentView>,
              let screenView = hostingView.findViewWithTag("DelugeScreenView") as? DelugeScreenView else {
            return
        }
        
        screenView.saveScreenshot()
    }
    
    var body: some View {
        ZStack {
            Color(midiManager.displayColorMode == .normal ? .black : .white)
                .ignoresSafeArea()
            
            if midiManager.isConnected {
                GeometryReader { geometry in
                    DelugeScreenView(
                        frameBuffer: midiManager.frameBuffer,
                        smoothingEnabled: midiManager.smoothingEnabled,
                        smoothingQuality: midiManager.smoothingQuality,
                        colorMode: midiManager.displayColorMode
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .aspectRatio(128/48, contentMode: .fit)
                .padding(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minWidth: 256, minHeight: 96)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    DelugeFont.renderText(
                        "WAITING FOR DELUGE",
                        color: midiManager.displayColorMode == .normal ? .white : .black
                    )
                    .frame(minHeight: 96)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 256, minHeight: 96)
        .onAppear {
            midiManager.setupMIDI()
        }
    }
}

extension NSView {
    func findViewWithTag(_ tag: String) -> NSView? {
        if let tagged = self.value(forKey: "tag") as? String, tagged == tag {
            return self
        }
        
        for subview in self.subviews {
            if let found = subview.findViewWithTag(tag) {
                return found
            }
        }
        
        return nil
    }
}

#Preview {
    ContentView()
}
