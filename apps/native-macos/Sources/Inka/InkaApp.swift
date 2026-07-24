import AppKit
import SwiftUI

/// Inka — the family's drawing & illustration app. macOS shell (P1 walking
/// skeleton): boots to the shared HomeScreen, opens a Metal canvas, paints with
/// the shared BrushKit/BrushRender engine, exports a PNG.
@main
struct InkaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .tint(.accentColor)
                .preferredColorScheme(.dark)
                .background(WindowBackdrop().ignoresSafeArea())
        }
        .windowToolbarStyle(.unified)
    }
}

/// The window's dark-glass backdrop, matching Fekthor's chrome.
struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
