import AppKit
import SwiftUI

struct TrackpadGestureMonitor: NSViewRepresentable {
    let onPan: (CGSize) -> Void
    let onMagnify: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPan: onPan, onMagnify: onMagnify)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onPan = onPan
        context.coordinator.onMagnify = onMagnify
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onPan: (CGSize) -> Void
        var onMagnify: (CGFloat) -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(onPan: @escaping (CGSize) -> Void, onMagnify: @escaping (CGFloat) -> Void) {
            self.onPan = onPan
            self.onMagnify = onMagnify
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self, let view = self.view, event.window === view.window else { return event }
                let location = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(location) else { return event }

                // If the cursor is over a scrollable panel list, let it scroll
                // instead of panning/zooming the canvas underneath.
                if self.isOverScrollableContent(event) { return event }

                switch event.type {
                case .scrollWheel:
                    guard event.phase != .cancelled else { return event }
                    self.onPan(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
                case .magnify:
                    self.onMagnify(event.magnification)
                default:
                    break
                }
                return event
            }
        }

        /// True when the event lands inside an NSScrollView (a panel's list),
        /// so canvas pan/zoom should defer to that scroll view.
        private func isOverScrollableContent(_ event: NSEvent) -> Bool {
            guard let content = view?.window?.contentView,
                  let hit = content.hitTest(event.locationInWindow) else { return false }
            var candidate: NSView? = hit
            while let current = candidate {
                if current is NSScrollView { return true }
                candidate = current.superview
            }
            return false
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stop()
        }
    }
}
