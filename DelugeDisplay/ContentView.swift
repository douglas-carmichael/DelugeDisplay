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
    @State private var screenViewRef: DelugeScreenView?
    
    func saveScreenshot() {
        guard midiManager.isConnected, let screenView = screenViewRef else { return }
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
                    .introspectDelugeScreenView { view in
                        screenViewRef = view
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .aspectRatio(128/48, contentMode: .fit)
                .padding(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minWidth: 256, minHeight: 96)
            } else {
                GeometryReader { geometry in
                    DelugeFont.renderText(
                        "WAITING FOR DELUGE",
                        color: midiManager.displayColorMode == .normal ? .white : .black
                    )
                }
                .aspectRatio(128/48, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minWidth: 256, minHeight: 96)
            }
        }
        .frame(minWidth: 256, minHeight: 96)
        .onAppear {
            midiManager.setupMIDI()
        }
    }
}

#Preview {
    ContentView()
}
