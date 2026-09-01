import AppKit
import SwiftUI

/// Keeps Slicer to a single window.
///
/// Slicer holds one source image in one model, so a second window is only ever
/// a duplicate *view* of the same session — edit a slice in one and it moves in
/// the other. SwiftUI's `WindowGroup` nonetheless opens a fresh window for
/// every Finder / Dock open request, so each new window checks in here and
/// closes itself if one is already up.
///
/// `Window` instead of `WindowGroup` would be the tidier fix, but the scene
/// never became visible to XCUITest, so this keeps the behaviour testable.
@MainActor
enum SlicerWindowCoordinator {
    private static weak var primary: NSWindow?

    static func adopt(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        guard let existing = primary, existing !== window, existing.isVisible else {
            primary = window
            return
        }

        // Closing a window while it is still being shown upsets AppKit, so let
        // this pass of the run loop finish first.
        DispatchQueue.main.async {
            window.close()
            existing.makeKeyAndOrderFront(nil)
        }
    }
}

/// Hands the enclosing `NSWindow` to a closure once the view is in one.
struct SlicerWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // `window` is still nil during `makeNSView`; it is set by the time the
        // view has been added to the hierarchy.
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
