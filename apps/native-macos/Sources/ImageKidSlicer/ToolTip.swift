import AppKit
import SwiftUI

/// An AppKit tooltip on a SwiftUI control.
///
/// Two simpler things were tried first and neither worked. SwiftUI's `.help()`
/// drew nothing on the floating tool bar. Setting `NSView.toolTip` on the
/// representable's own view did not work either: SwiftUI hosts a `.background`
/// representable in a container that sits *behind* the control and is
/// sometimes laid out beyond its parent's bounds — dumping the real hierarchy
/// showed hosts at x=161 inside 41-point-wide parents at x=47 — so the view
/// carrying the tooltip is clipped and never consulted.
///
/// What does work is registering a tooltip *rect* on an ancestor that is
/// correctly framed and on top: `addToolTip(_:owner:userData:)` is exactly that API. The
/// annotation measures itself in the root view's coordinates and registers
/// there, re-registering whenever it moves.
private struct ToolTipAnnotation: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> ToolTipProbeView {
        let view = ToolTipProbeView()
        view.tip = text
        return view
    }

    func updateNSView(_ nsView: ToolTipProbeView, context: Context) {
        nsView.tip = text
    }

    static func dismantleNSView(_ nsView: ToolTipProbeView, coordinator: ()) {
        nsView.unregister()
    }
}

/// Measures the control it is placed behind, and keeps a tooltip rect for it
/// registered on the root view.
final class ToolTipProbeView: NSView, NSViewToolTipOwner {
    var tip: String = "" {
        didSet { register() }
    }

    private var toolTipTag: NSView.ToolTipTag?
    private weak var host: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Frame changes are the signal that the rect has to move; a plain
        // NSView is not laid out often enough to rely on `layout()`.
        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(frameChanged),
            name: NSView.frameDidChangeNotification, object: self
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Never take a click: this view exists only to describe the control in
    /// front of it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        register()
    }

    override func layout() {
        super.layout()
        register()
    }

    @objc private func frameChanged() { register() }

    /// The view every rect is registered on: the top of the hierarchy, which
    /// is on top of the content and covers all of it.
    private func rootView() -> NSView? {
        var candidate: NSView? = self
        var root: NSView?
        while let current = candidate {
            root = current
            candidate = current.superview
        }
        return root === self ? nil : root
    }

    func register() {
        unregister()
        guard window != nil, !tip.isEmpty, let root = rootView() else { return }

        let rect = convert(bounds, to: root)
        guard rect.width > 1, rect.height > 1 else { return }

        toolTipTag = root.addToolTip(rect, owner: self, userData: nil)
        host = root
    }

    func unregister() {
        if let toolTipTag, let host { host.removeToolTip(toolTipTag) }
        toolTipTag = nil
        host = nil
    }

    /// The rect currently registered, in the root view's coordinates — nil
    /// when nothing is registered. Used by the tests to prove the geometry.
    var registeredRect: CGRect? {
        guard toolTipTag != nil, let host else { return nil }
        return convert(bounds, to: host)
    }

    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData: UnsafeMutableRawPointer?
    ) -> String {
        tip
    }
}

extension View {
    /// Describe this control on hover.
    ///
    /// `.help()` is applied alongside, since that is what carries the text
    /// into the accessibility tree even where it draws nothing.
    func toolTip(_ text: String) -> some View {
        help(text).background(ToolTipAnnotation(text: text))
    }
}
