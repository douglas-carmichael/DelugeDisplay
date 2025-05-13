
//
//  SettingsView.swift
//  DelugeDisplay
//
//  Created by Alex (AI Assistant) on [Current Date].
//

import SwiftUI
import CoreMIDI // For MIDIManager.MIDIPort

#if os(iOS)
struct SettingsView: View {
    @EnvironmentObject var midiManager: MIDIManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("MIDI")) {
                    if midiManager.availablePorts.isEmpty {
                        VStack(alignment: .leading) {
                            Text("No MIDI Ports Available.")
                                .foregroundColor(.secondary)
                            Text("Connect your Deluge and ensure it's enabled for MIDI.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        Picker("Port", selection: $midiManager.selectedPort) {
                            Text("Not Connected").tag(nil as MIDIManager.MIDIPort?)
                            ForEach(midiManager.availablePorts) { port in
                                Text(port.name).tag(port as MIDIManager.MIDIPort?)
                            }
                        }
                    }
                    Button("Rescan MIDI Ports") {
                        midiManager.scanAvailablePorts()
                    }
                }

                Section(header: Text("Display Mode")) {
                    Picker("Mode", selection: $midiManager.displayMode) {
                        Text("OLED").tag(DelugeDisplayMode.oled)
                        Text("7-Segment").tag(DelugeDisplayMode.sevenSegment)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("Appearance")) {
                    Picker("Color Scheme", selection: $midiManager.displayColorMode) {
                        ForEach(DelugeDisplayColorMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    
                    Toggle("Image Smoothing", isOn: $midiManager.smoothingEnabled)
                    
                    if midiManager.smoothingEnabled {
                        Picker("Smoothing Quality", selection: $midiManager.smoothingQuality) {
                            Text("Low").tag(Image.Interpolation.low)
                            Text("Medium").tag(Image.Interpolation.medium)
                            Text("High").tag(Image.Interpolation.high)
                        }
                    }
                    
                    if midiManager.displayMode == .oled {
                        Toggle("OLED Pixel Grid", isOn: $midiManager.oledPixelGridModeEnabled)
                    }
                }
                
                Section(header: Text("About")) {
                    NavigationLink("About DelugeDisplay", destination: AboutView().environmentObject(midiManager))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        // Apply .navigationViewStyle(.stack) to ensure it behaves correctly within a sheet,
        // especially on iPad if the main view ever uses a different style.
        .navigationViewStyle(.stack)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(MIDIManager())
    }
}
#endif
