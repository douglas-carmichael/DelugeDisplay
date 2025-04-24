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
    @State private var viewSize: CGSize = CGSize(width: 512, height: 192)
    
    var body: some View {
        ZStack {
            Color.black // Background that fills the entire window
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
                .aspectRatio(8/3, contentMode: .fit)
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
