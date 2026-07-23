import CoreGraphics
import SwiftUI
import UIKit

/// A placed image layer over the base picture. `frame` is normalised (0…1) in
/// the base image's space (top-left origin). Non-destructive: only flattened on
/// export, never baked into the base.
struct EditorLayer: Identifiable {
    let id = UUID()
    var name: String
    var image: UIImage
    var frame: CGRect
    var opacity: Double = 1
    var isVisible: Bool = true

    /// A copy translated by a normalised delta.
    func translated(dx: CGFloat, dy: CGFloat) -> EditorLayer {
        var copy = self
        copy.frame.origin = CGPoint(x: frame.minX + dx, y: frame.minY + dy)
        return copy
    }

    /// A copy scaled about its centre by `factor` (clamped to a sane range).
    func scaled(by factor: CGFloat) -> EditorLayer {
        var copy = self
        let f = min(max(factor, 0.05), 8)
        let newW = frame.width * f
        let newH = frame.height * f
        copy.frame = CGRect(
            x: frame.midX - newW / 2, y: frame.midY - newH / 2,
            width: newW, height: newH
        )
        return copy
    }
}

enum LayerCompositor {
    /// Flatten image layers onto a base image at full resolution (used for
    /// view-mode display and export). Returns the base unchanged if none.
    static func render(base: CGImage, layers: [EditorLayer]) -> CGImage? {
        let visible = layers.filter { $0.isVisible }
        guard !visible.isEmpty else { return base }
        let size = CGSize(width: base.width, height: base.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let output = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: base).draw(in: CGRect(origin: .zero, size: size))
            for layer in visible {
                let rect = CGRect(
                    x: layer.frame.minX * size.width,
                    y: layer.frame.minY * size.height,
                    width: layer.frame.width * size.width,
                    height: layer.frame.height * size.height
                )
                layer.image.draw(in: rect, blendMode: .normal, alpha: CGFloat(layer.opacity))
            }
        }
        return output.cgImage
    }
}
