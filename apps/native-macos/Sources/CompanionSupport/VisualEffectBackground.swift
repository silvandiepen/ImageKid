import AppKit
import SwiftUI

/// Behind-window blur for the companion windows. SwiftUI has no first-party way to
/// make a window's own background translucent on macOS 14, so this wraps the
/// AppKit view at the single point where it is needed.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// Makes the host window participate in behind-window compositing. A visual
/// effect view alone still resolves against an opaque window background.
struct CompanionWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
    }
}

/// Alpha checkerboard, so a transparent cutout preview reads as transparent
/// instead of as a hole in the dark chrome.
struct CheckerboardBackground: View {
    var square: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.16)))
            let columns = Int(ceil(size.width / square))
            let rows = Int(ceil(size.height / square))
            for row in 0..<max(rows, 1) {
                for column in 0..<max(columns, 1) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * square,
                        y: CGFloat(row) * square,
                        width: square,
                        height: square
                    )
                    context.fill(Path(rect), with: .color(.black.opacity(0.22)))
                }
            }
        }
        .drawingGroup()
    }
}
