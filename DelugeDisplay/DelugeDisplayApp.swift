//
//  DelugeDisplayApp.swift
//  DelugeDisplay
//
//  Created by Douglas Carmichael on 4/21/25.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

@main
struct DelugeDisplayApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(iOSAppDelegate.self) var iOSDelegate
    #endif
    
    @StateObject private var midiManager = MIDIManager()

    init() {
        #if os(macOS)
        NSWindow.allowsAutomaticWindowTabbing = false
        // Pass the single MIDIManager instance to the macOS AppDelegate
        // This needs to happen after appDelegate is initialized.
        // Better to do this in onAppear or by making appDelegate observe the StateObject.
        // For now, let's use onAppear for consistency.
        #endif
        #if DEBUG
        print("DelugeDisplayApp init.")
        #endif
    }
    
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(midiManager) // This is correct
                .onAppear {
                    #if os(macOS)
                    if appDelegate.midiManager == nil {
                        appDelegate.midiManager = self.midiManager
                        #if DEBUG
                        print("MIDIManager instance passed to macOS AppDelegate from onAppear.")
                        #endif
                    }
                    #elseif os(iOS)
                    if iOSDelegate.midiManager == nil { 
                        iOSDelegate.midiManager = self.midiManager 
                        #if DEBUG
                        print("MIDIManager instance passed to iOSDelegate from onAppear.")
                        #endif
                    }
                    #endif
                }
        }
        #if os(macOS)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 384, height: 192) 
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
            
            CommandGroup(replacing: .sidebar) { 
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
            CommandGroup(replacing: .appInfo) {
                 Button("About DelugeDisplay") {
                     appDelegate.showAboutWindow()
                 }
             }
        }
        #endif // End of os(macOS) for window modifiers and commands
        .onChange(of: scenePhase) { newPhase in
            #if os(iOS) 
            if newPhase == .background {
                #if DEBUG
                print("iOS App moving to background. Current MIDI status: \(midiManager.isConnected)")
                #endif
            } else if newPhase == .active {
                #if DEBUG
                print("iOS App moving to active.")
                #endif
            }
            #endif
        }
    }

    #if os(macOS)
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
                midiManager.scanAvailablePorts()
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
    #endif // End of os(macOS) for menu item views
}
