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
        ZStack {
            Color(midiManager.displayColorMode == .normal ? .black : .white)
                .ignoresSafeArea()
            
            if midiManager.isConnected {
                if midiManager.displayMode == .oled {
                    GeometryReader { geometry in
                        DelugeScreenView()
                        // If DelugeScreenView needs to expose its saveScreenshot instance method,
                        // it would typically be done by calling a method on midiManager that then interacts with its state.
                        // For simplicity, we changed saveScreenshot() above to use the static DelugeScreenView method.
                        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                    }
                    .aspectRatio(128.0/48.0, contentMode: .fit) // Ensure floating point for aspect ratio
                    .padding(2)
                    .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                    .frame(minWidth: 256, minHeight: 96)
                } else {
                    GeometryReader { geometry in
                        SevenSegmentDisplayView(availableSize: geometry.size) // CORRECTED: Pass geometry.size
                            .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                    }
                    .aspectRatio(128.0/48.0, contentMode: .fit) // You might need a different aspect ratio or layout for 7-segment
                    .padding(2)
                    .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                    .frame(minWidth: 256, minHeight: 96) // Adjust minWidth/Height if needed for 7-segment
                }
            } else {
                GeometryReader { geometry in
                    DelugeFont.renderText(
                        "WAITING FOR DELUGE",
                        color: midiManager.displayColorMode == .normal ? .white : .black
                    )
                }
                .aspectRatio(128.0/48.0, contentMode: .fit) // Ensure floating point
                .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                .frame(minWidth: 256, minHeight: 96)
            }
        }
        .frame(minWidth: 256, minHeight: 96)
        .onAppear {
            // midiManager.setupMIDI() // setupMIDI is called in MIDIManager's init.
            // Re-evaluating if this is needed here or if init is sufficient.
            // If ports can change or need re-scanning on appear, it might be useful.
            // For now, assuming MIDIManager handles its own setup.
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MIDIManager())
}
