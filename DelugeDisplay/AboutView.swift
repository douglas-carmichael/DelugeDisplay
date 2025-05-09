import SwiftUI
#if os(iOS)
import UIKit
#endif

struct AboutView: View {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    
    var body: some View {
        VStack(spacing: 16) {
            #if os(macOS)
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 128, height: 128)
            #elseif os(iOS)
            Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                .resizable()
                .frame(width: 128, height: 128)
            #else
            Image(systemName: "app.dashed") 
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
            #endif
            
            Text("DelugeDisplay")
                .font(.system(size: 13, weight: .semibold))
            
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Text("A companion display app for the Synthstrom Deluge")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            Text(" 2025 Douglas Carmichael")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        #if os(macOS)
        .frame(width: 400) 
        #endif
        .padding(20)
    }
}

#Preview {
    AboutView()
        .environmentObject(MIDIManager()) 
}
