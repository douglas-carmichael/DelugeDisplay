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
    @State private var showingSettingsSheet = false
    #if os(iOS)
    @State private var showingScreenshotShareSheet = false
    // This would ideally be UIImage or Data for UIActivityViewController
    @State private var screenshotDataForSharing: Data? 
    #endif

    var body: some View {
        #if os(iOS)
        ZStack {
            mainContent
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showingSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .padding(16)
                }
                Spacer()
            }
            
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsView()
                .environmentObject(midiManager)
        }
        #else
        // Original content for macOS (no NavigationView or iOS toolbars)
        mainContent
        #endif
    }

    private var mainContent: some View {
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
                                color: midiManager.displayColorMode == .normal ? .white : (midiManager.displayColorMode == .matrix ? Color(red: 0, green: 0.8, blue: 0) : .black)
                            )
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
            // midiManager.setupMIDI() // This is usually handled by MIDIManager's init or port selection logic
        }
    }

    #if os(iOS)
    func generateAndShareScreenshot_iOS() {
        guard midiManager.isConnected else { return }
        
        // --- STUBBED ---
        // In a real implementation, you would:
        // 1. Get the image data (e.g., UIImage or raw pixel Data) from DelugeScreenView or SevenSegmentDisplayView.
        //    This might involve rendering the view to an image, or constructing an image from `frameBuffer`/`sevenSegmentDigits`.
        //    For example:
        //    let imageData = DelugeScreenView.getScreenshotData(midiManager: midiManager)
        //    self.screenshotDataForSharing = imageData
        //    self.showingScreenshotShareSheet = imageData != nil
        
        // For now, we'll just toggle the sheet with a placeholder.
        self.screenshotDataForSharing = "Placeholder screenshot data".data(using: .utf8) // Simulate some data
        self.showingScreenshotShareSheet = true
        print("iOS: Attempting to generate and share screenshot (currently stubbed).")
        // --- END STUB ---
    }
    #endif
}
