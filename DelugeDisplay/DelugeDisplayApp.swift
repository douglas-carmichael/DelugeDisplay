//
//  DelugeDisplayApp.swift
//  DelugeDisplay
//
//  Created by Douglas Carmichael on 4/21/25.
//

import SwiftUI

@main
struct DelugeDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var midiManager = MIDIManager()
    @State private var displayMode: DelugeDisplayMode = .oled

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
                get: { displayMode == .oled },
                set: { if $0 { displayMode = .oled } }
            ))
            .keyboardShortcut("1", modifiers: .command)
            
            Toggle("Show 7SEG", isOn: Binding(
                get: { displayMode == .sevenSegment },
                set: { if $0 { displayMode = .sevenSegment } }
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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(midiManager)
                .frame(minWidth: 192, minHeight: 96)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 192, height: 96)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About DelugeDisplay") {
                    appDelegate.showAboutWindow()
                }
                
                Divider()
                
                Button("Hide DelugeDisplay") {
                    NSApplication.shared.hide(nil)
                }
                .keyboardShortcut("h", modifiers: .command)
                
                Button("Hide Others") {
                    NSApplication.shared.hideOtherApplications(nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .option])
                
                Button("Show All") {
                    NSApplication.shared.unhideAllApplications(nil)
                }
                
                Divider()
                
                Button("Quit DelugeDisplay") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            
            CommandGroup(replacing: .sidebar) {
                displayModeMenu
                
                Divider()
                
                displayColorMenu
                
                Divider()
                
                zoomControls
                
                Divider()
                
                smoothingControls
            }
            
            CommandMenu("MIDI") {
                midiPortItems
            }
        }
    }
}
