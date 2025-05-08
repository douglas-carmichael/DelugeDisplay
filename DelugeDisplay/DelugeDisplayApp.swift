//
//  DelugeDisplayApp.swift
//  DelugeDisplay
//
//  Created by Douglas Carmichael on 4/21/25.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct DelugeDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var midiManager = MIDIManager()
    // @State private var displayMode: DelugeDisplayMode = .oled

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    
    private var midiPortItems: some View {
        Group {
            if midiManager.availablePorts.isEmpty {
                Text("No MIDI Ports Available")
            } else {
                ForEach(midiManager.availablePorts) { port in
                    Toggle(port.name, isOn: Binding(
                        get: { midiManager.selectedPort?.id == port.id },
                        set: { if $0 { midiManager.selectedPort = port } }
                    ))
                }
            }
            
            Divider()
            
            Button("Rescan MIDI Ports") {
                midiManager.setupMIDI()
            }
        }
    }
    
    private var displayModeMenu: some View {
        Group {
            Toggle("Show OLED", isOn: Binding(
                get: { midiManager.displayMode == .oled },
                set: { if $0 { midiManager.displayMode = .oled } }
            ))
            .keyboardShortcut("1", modifiers: .command)
            
            Toggle("Show 7SEG", isOn: Binding(
                get: { midiManager.displayMode == .sevenSegment },
                set: { if $0 { midiManager.displayMode = .sevenSegment } }
            ))
            .keyboardShortcut("2", modifiers: .command)
        }
    }
    
    private var displayColorMenu: some View {
        Menu("Display Colors") {
            ForEach(DelugeDisplayColorMode.allCases, id: \.self) { mode in
                Toggle(mode.rawValue, isOn: Binding(
                    get: { midiManager.displayColorMode == mode },
                    set: { if $0 { midiManager.displayColorMode = mode } }
                ))
            }
        }
    }
    
    private var zoomControls: some View {
        Group {
            Button("Actual Size") {
                if let window = NSApplication.shared.windows.first {
                    appDelegate.resetToMinimumSize(window: window)
                }
            }
            .keyboardShortcut("0", modifiers: .command)
            
            Button("Zoom In") {
                if let window = NSApplication.shared.windows.first {
                    appDelegate.resizeWindow(scale: 1.25, window: window)
                }
            }
            .keyboardShortcut("+", modifiers: .command)
            
            Button("Zoom Out") {
                if let window = NSApplication.shared.windows.first {
                    appDelegate.resizeWindow(scale: 0.8, window: window)
                }
            }
            .keyboardShortcut("-", modifiers: .command)
        }
    }
    
    private var smoothingControls: some View {
        Group {
            Toggle("Enable Smoothing", isOn: $midiManager.smoothingEnabled)
                .keyboardShortcut("s", modifiers: .command)
            
            Picker("Smoothing Quality", selection: $midiManager.smoothingQuality) {
                Text("Low").tag(Image.Interpolation.low)
                Text("Medium").tag(Image.Interpolation.medium)
                Text("High").tag(Image.Interpolation.high)
            }
            .disabled(!midiManager.smoothingEnabled)
        }
    }
    
    private var pixelGridToggle: some View {
        Toggle("Pixel Grid", isOn: $midiManager.oledPixelGridModeEnabled)
            .keyboardShortcut("g", modifiers: .command)
            .disabled(midiManager.displayMode != .oled)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(midiManager)
                .frame(minWidth: 192, minHeight: 96) // Consider if this minHeight needs to be 140 as in ContentView or if ContentView's is sufficient
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 384, height: 192) // This is the initial size
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Save Screenshot...") {
                    if midiManager.isConnected {
                        DelugeScreenView.saveScreenshotFromCurrentDisplay(midiManager: midiManager)
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!midiManager.isConnected)
            }
            
            CommandGroup(replacing: .sidebar) { // This is the main "View" menu
                displayModeMenu
                Divider()
                displayColorMenu
                Divider()
                zoomControls
                Divider()
                smoothingControls
                Divider()
                pixelGridToggle
            }
            
            CommandMenu("MIDI") {
                midiPortItems
            }
            
            CommandGroup(replacing: .saveItem) { }
        }
    }
}
