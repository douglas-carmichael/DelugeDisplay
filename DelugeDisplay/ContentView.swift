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
            Color.black
                .ignoresSafeArea()
            
            if midiManager.isConnected {
                GeometryReader { geometry in
                    DelugeScreenView(
                        frameBuffer: midiManager.frameBuffer,
                        smoothingEnabled: midiManager.smoothingEnabled,
                        smoothingQuality: midiManager.smoothingQuality
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .aspectRatio(128/48, contentMode: .fit)
                .padding(.top, 40)
                .padding(.bottom, 52)
                .padding(.horizontal, 20)
            } else {
                Text("Waiting for Deluge connection...")
                    .foregroundColor(.white)
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
