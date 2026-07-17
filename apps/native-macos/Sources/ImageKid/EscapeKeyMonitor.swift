import SwiftUI

struct EscapeKeyMonitor: NSViewRepresentable {
    let onEscape: () -> Void
    let onDelete: () -> Bool
    let onCommit: () -> Bool

    func makeNSView(context: Context) -> EscapeKeyMonitorView {
        let view = EscapeKeyMonitorView()
        view.onEscape = onEscape
        view.onDelete = onDelete
        view.onCommit = onCommit
        return view
    }

    func updateNSView(_ nsView: EscapeKeyMonitorView, context: Context) {
        nsView.onEscape = onEscape
        nsView.onDelete = onDelete
        nsView.onCommit = onCommit
    }
}

final class EscapeKeyMonitorView: NSView {
    var onEscape: (() -> Void)?
    var onDelete: (() -> Bool)?
    var onCommit: (() -> Bool)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.onEscape?()
                return nil
            }

            if event.keyCode == 51 || event.keyCode == 117 {
                guard !self.isEditingText else { return event }
                return self.onDelete?() == true ? nil : event
            }

            if event.keyCode == 36 || event.keyCode == 76 {
                guard !self.isEditingText else { return event }
                return self.onCommit?() == true ? nil : event
            }

            return event
        }
    }

    private var isEditingText: Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder is NSTextView { return true }
        if responder is NSTextField { return true }
        return false
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
