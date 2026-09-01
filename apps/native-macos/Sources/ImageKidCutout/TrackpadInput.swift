import AppKit
import SwiftUI

/// Trackpad scroll and pinch for the editor canvas.
///
/// SwiftUI has no scroll-wheel event on macOS, and a `MagnifyGesture` does not say
/// where the pinch happened, which is what anchored zooming needs. Rather than an
/// AppKit view in the responder chain — which would have to sit above the canvas and
/// would then swallow the brush's mouse events — this watches events locally and only
/// claims the ones inside its own bounds.
struct TrackpadInput: NSViewRepresentable {
    /// Scroll delta in points, plus the modifiers held at the time.
    var onScroll: (CGSize, NSEvent.ModifierFlags) -> Void
    /// Pinch magnification delta, and where in the view it happened.
    var onMagnify: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> TrackpadEventView {
        let view = TrackpadEventView()
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        return view
    }

    func updateNSView(_ view: TrackpadEventView, context: Context) {
        view.onScroll = onScroll
        view.onMagnify = onMagnify
    }

    static func dismantleNSView(_ view: TrackpadEventView, coordinator: ()) {
        view.stopWatching()
    }
}

final class TrackpadEventView: NSView {
    var onScroll: ((CGSize, NSEvent.ModifierFlags) -> Void)?
    var onMagnify: ((CGFloat, CGPoint) -> Void)?

    private var monitor: Any?

    /// Top-left origin, so the points handed back match SwiftUI's coordinate space.
    override var isFlipped: Bool { true }

    /// Invisible to the mouse. SwiftUI's `allowsHitTesting(false)` does not stop an
    /// AppKit view from taking mouse events, and this one sits above the canvas — left
    /// alone it swallows the brush's clicks and the hover that draws the cursor. Scroll
    /// and pinch still arrive, because they come from the event monitor rather than
    /// from hit testing.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopWatching()
        } else {
            startWatching()
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func stopWatching() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func startWatching() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard
                let self,
                let window = self.window,
                event.window === window
            else {
                return event
            }

            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else { return event }

            switch event.type {
            case .scrollWheel:
                self.onScroll?(
                    CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
                    event.modifierFlags
                )
            case .magnify:
                self.onMagnify?(event.magnification, point)
            default:
                return event
            }
            return nil
        }
    }
}
