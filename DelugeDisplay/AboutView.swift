import SwiftUI

struct AboutView: View {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 128, height: 128)
            
            Text("DelugeDisplay")
                .font(.title)
            
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
            
            Text("A companion display app for the Synthstrom Deluge")
                .multilineTextAlignment(.center)
            
            Text("© 2025 Douglas Carmichael")
                .font(.caption)
                .padding(.top)
        }
        .frame(width: 320)
        .padding(20)
    }
}