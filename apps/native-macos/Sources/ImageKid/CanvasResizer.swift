import AppKit

/// Where the existing content sits when the canvas grows or shrinks.
enum CanvasAnchor: String, CaseIterable, Identifiable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight

    var id: String { rawValue }

    /// Horizontal / vertical placement fraction (0 = left/top, 1 = right/bottom).
    var unit: (x: CGFloat, y: CGFloat) {
        switch self {
        case .topLeft: return (0, 0)
        case .top: return (0.5, 0)
        case .topRight: return (1, 0)
        case .left: return (0, 0.5)
        case .center: return (0.5, 0.5)
        case .right: return (1, 0.5)
        case .bottomLeft: return (0, 1)
        case .bottom: return (0.5, 1)
        case .bottomRight: return (1, 1)
        }
    }

    var symbol: String {
        switch self {
        case .topLeft: "arrow.up.left"
        case .top: "arrow.up"
        case .topRight: "arrow.up.right"
        case .left: "arrow.left"
        case .center: "dot.square"
        case .right: "arrow.right"
        case .bottomLeft: "arrow.down.left"
        case .bottom: "arrow.down"
        case .bottomRight: "arrow.down.right"
        }
    }
}

/// Places existing content onto a new canvas size — adding transparent (or
/// filled) margin, or cropping — without scaling the content, anchored by a grid.
enum CanvasResizer {
    static func place(_ image: NSImage, onCanvas size: CGSize, anchor: CanvasAnchor, fill: NSColor?) -> NSImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        let content = image.size
        let out = NSImage(size: size)
        out.lockFocus()
        defer { out.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high

        if let fill {
            fill.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        }

        let (fx, fy) = anchor.unit
        let x = (size.width - content.width) * fx
        // AppKit is bottom-left origin; map the top-based anchor to a y-up origin.
        let y = (size.height - content.height) * (1 - fy)
        image.draw(
            in: CGRect(x: x, y: y, width: content.width, height: content.height),
            from: .zero, operation: .sourceOver, fraction: 1
        )
        return out
    }
}
