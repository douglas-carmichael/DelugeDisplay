//
//  DelugeDisplayApp.swift
//  DelugeDisplay
//
//  Created by Douglas Carmichael on 4/21/25.
//

import SwiftUI

@main
struct DelugeDisplayApp: App {
    @State private var displayMode: DelugeDisplayMode = .oled

    init()
    {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
        .commands {
            // Replace all standard menus with empty ones
            CommandGroup(replacing: .appInfo) {
                // About group
                Button("About DelugeDisplay") {
                    // About action
                }
                
                Divider()
                
                // Preferences group
                Button("Preferences...") {
                    // Preferences action
                }
                .keyboardShortcut(",", modifiers: .command)
                
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
            
            // Custom View menu only
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
            }
        }
    }
}
