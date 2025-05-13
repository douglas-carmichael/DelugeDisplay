
//
//  iOSAppDelegate.swift
//  DelugeDisplay
//
//  Created by Alex (AI Assistant) on [Current Date].
//

import UIKit
import SwiftUI // Required for @ObservedObject or similar if directly accessing MIDIManager properties from App

#if os(iOS)
class iOSAppDelegate: NSObject, UIApplicationDelegate {
    
    // This property will be set from DelugeDisplayApp
    var midiManager: MIDIManager?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Perform any initial iOS-specific setup if needed
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // This is called when the app is about to terminate.
        // Ensure MIDI resources are released.
        #if DEBUG
        print("iOSAppDelegate: applicationWillTerminate - Calling midiManager.disconnect()")
        #endif
        // midiManager is @MainActor, applicationWillTerminate is called on the main thread.
        midiManager?.disconnect()
    }
    
    // You can also handle other iOS specific lifecycle events here if necessary,
    // like backgrounding, foregrounding, push notifications, etc.
}
#endif
