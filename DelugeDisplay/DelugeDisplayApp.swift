//
//  DelugeDisplayApp.swift
//  DelugeDisplay
//
//  Created by Douglas Carmichael on 4/21/25.
//

import SwiftUI

@main
struct DelugeDisplayApp: App {
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
        }
    }
}
