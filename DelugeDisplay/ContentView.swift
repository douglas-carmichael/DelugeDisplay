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
                Text("Waiting for Deluge connection...")
                    .foregroundColor(midiManager.displayColorMode == .normal ? .white : .black)
            }
        }
        .onAppear {
            midiManager.setupMIDI()
        }
    }
}

#Preview {
    ContentView()
}
