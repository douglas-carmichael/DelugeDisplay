//
//  ContentView.swift
//  DelugeDisplay
//
//  Created by Douglas Carmichael on 4/21/25.
//

import SwiftUI
import CoreMIDI

struct ContentView: View {
    @StateObject private var midiManager = MIDIManager()
    
    var body: some View {
        VStack {
            if midiManager.isConnected {
                DelugeScreenView(frameBuffer: midiManager.frameBuffer)
                    .frame(width: 512, height: 192) // 4x scale
            } else {
                Text("Waiting for Deluge connection...")
            }
            
            HStack {
                Button("Connect") {
                    midiManager.setupMIDI()
                }
                .disabled(midiManager.isConnected)
                
                Button("Disconnect") {
                    midiManager.disconnect()
                }
                .disabled(!midiManager.isConnected)
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
