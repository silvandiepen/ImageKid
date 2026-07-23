import SwiftUI

#if os(macOS)
import AppKit

/// Locates the enclosing NSScrollView of a SwiftUI ScrollView and forces the
/// thin, auto-hiding overlay scroller style regardless of the system's
/// "Show scroll bars" setting.
private struct ThinScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in Self.configure(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in Self.configure(from: nsView) }
    }

    private static func configure(from view: NSView?) {
        guard let scrollView = view?.enclosingScrollView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.horizontalScroller?.controlSize = .mini
        scrollView.drawsBackground = false
    }
}

public extension View {
    /// Apply thin, auto-hiding overlay scrollbars to the enclosing scroll view.
    /// Place on the scroll view's content (e.g. as a background).
    func thinScrollbars() -> some View {
        background(ThinScrollerConfigurator().frame(width: 0, height: 0))
    }
}
#else
public extension View {
    func thinScrollbars() -> some View { self }
}
#endif
