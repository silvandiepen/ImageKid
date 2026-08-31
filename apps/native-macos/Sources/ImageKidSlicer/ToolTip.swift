import AppKit
import SwiftUI

/// An AppKit tooltip on a SwiftUI view.
///
/// SwiftUI's `.help()` is the obvious way to do this and it did not show
/// anything on the floating tool bar — most likely because those buttons sit
/// in an overlay above a canvas that owns a zero-distance drag gesture. Rather
/// than guess at SwiftUI's tracking, this sets `NSView.toolTip` on the real
/// backing view, which is the thing AppKit actually consults.
///
/// The trick is the direction: the representable's own view is *inside* the
/// view being described, so it annotates its `superview` — the container
/// SwiftUI made for the button — rather than itself. Annotating itself would
/// need it to be hit-testable, and a hit-testable overlay would swallow the
/// click meant for the button underneath.
private struct ToolTipAnnotation: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> AnnotatingView {
        let view = AnnotatingView()
        view.text = text
        return view
    }

    func updateNSView(_ nsView: AnnotatingView, context: Context) {
        nsView.text = text
    }

    final class AnnotatingView: NSView {
        var text: String? {
            didSet { annotate() }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            annotate()
        }

        /// Never take a click: this view exists only to label its container.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func annotate() {
            superview?.toolTip = text
        }
    }
}

extension View {
    /// Describe this control on hover.
    ///
    /// Also applies `.help()`, which is what carries the text into the
    /// accessibility tree even where it does not draw a tooltip.
    func toolTip(_ text: String) -> some View {
        help(text).background(ToolTipAnnotation(text: text))
    }
}
