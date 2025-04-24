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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(midiManager)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 512, height: 192)
        .commandsRemoved()
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About DelugeDisplay") {
                    appDelegate.showAboutWindow()
                }
                
                Divider()
                
                // Services group (empty but keeping divider for HIG compliance)
                Divider()
                
                // Application termination group
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
            
            // Custom View menu
            CommandGroup(replacing: .sidebar) {
                Divider()
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
                
                Divider()
                
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
    }
}
