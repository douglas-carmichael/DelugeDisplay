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
    // @State private var screenViewRef: DelugeScreenView? // This might not be easily obtainable now

    // If DelugeScreenView.saveScreenshot() is an instance method, we need an instance.
    // If it's static or on MIDIManager, call it that way.
    // For now, let's assume DelugeScreenView's instance method is callable via midiManager if it makes sense,
    // or we call the static one.
    // The current DelugeScreenView.saveScreenshot() is an instance method.
    // Let's try calling the static method from DelugeScreenView for now,
    // as getting a ref to the View struct itself can be tricky.
    func saveScreenshot() {
        guard midiManager.isConnected else { return }
        // Call the static method on DelugeScreenView, passing the midiManager
        DelugeScreenView.saveScreenshotFromCurrentDisplay(midiManager: midiManager)
    }
    
    var body: some View {
        ZStack { // Root ZStack for background color
            Color(midiManager.displayColorMode == .inverted ? .white : .black)
                .ignoresSafeArea()
            
            VStack(spacing: 0) { // Main content VStack

                // Display Area (OLED, 7-Segment, or Waiting Message)
                ZStack {
                    // The content of the ZStack will be centered.
                    if midiManager.isConnected {
                        if midiManager.displayMode == .oled {
                            DelugeScreenView() 
                        } else { // SevenSegment (already connected)
                            GeometryReader { geometryInZStack in
                                SevenSegmentDisplayView(availableSize: geometryInZStack.size)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    } else { // Not connected, show waiting message
                        GeometryReader { geometryInZStack in
                            DelugeFont.renderText(
                                "WAITING FOR DELUGE",
                                color: midiManager.displayColorMode == .normal ? .white : (midiManager.displayColorMode == .green_on_black ? Color(red: 0, green: 0.8, blue: 0) : .black))
                        }
                    }
                }
                .aspectRatio(128.0/48.0, contentMode: .fit) // Apply aspect ratio to the ZStack
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Allow ZStack to use flexible space
                .frame(minWidth: 256, minHeight: 96)      // Minimum size for the ZStack
                .layoutPriority(1)                          // Give display area priority for space

            } // End main content VStack
        } // End root ZStack
        .frame(minWidth: 256, minHeight: 96) 
        .onAppear {
            // midiManager.setupMIDI()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MIDIManager())
}
