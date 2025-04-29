import SwiftUI

extension View {
    func introspectDelugeScreenView(customize: @escaping (DelugeScreenView) -> ()) -> some View {
        return background(IntrospectionView(customize: customize))
    }
}

private struct IntrospectionView: NSViewRepresentable {
    let customize: (DelugeScreenView) -> ()
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let delugeScreenView = view.superview?.superview as? DelugeScreenView else { return }
            customize(delugeScreenView)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}