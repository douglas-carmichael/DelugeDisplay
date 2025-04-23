import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    @ObservedObject var midiManager = MIDIManager()
    
    func applicationWillTerminate(_ notification: Notification) {
        midiManager.disconnect()
    }
}