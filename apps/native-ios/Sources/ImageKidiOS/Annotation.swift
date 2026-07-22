import CoreGraphics
import Foundation
import SwiftUI

/// A single annotation stored in normalised (0…1, top-left origin) coordinates
/// so it renders identically in the editor and when flattened at full
/// resolution. Geometry is produced as a `CGPath`, shared by the SwiftUI
/// `Canvas` preview and the UIKit rasteriser.
struct Annotation: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case rectangle
        case ellipse
        case line
        case arrow
        case freehand
        case text

        var id: String { rawValue }

        var label: String {
            switch self {
            case .rectangle: return "Rectangle"
            case .ellipse: return "Ellipse"
            case .line: return "Line"
            case .arrow: return "Arrow"
            case .freehand: return "Draw"
            case .text: return "Text"
            }
        }

        var systemImage: String {
            switch self {
            case .rectangle: return "rectangle"
            case .ellipse: return "circle"
            case .line: return "line.diagonal"
            case .arrow: return "arrow.up.right"
            case .freehand: return "scribble"
            case .text: return "textformat"
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var color: Color
    /// Stroke width as a fraction of the image's smaller side (resolution-free).
    var widthFraction: CGFloat
    var start: CGPoint = .zero
    var end: CGPoint = .zero
    var points: [CGPoint] = []
    /// Text content and size (fraction of image height) for `.text` annotations.
    var text: String = ""
    var fontFraction: CGFloat = 0.05
    /// Hidden layers stay in the stack but are skipped by the editor canvas
    /// and the rasteriser (toggled from the Layers panel's eye button).
    var isHidden = false

    var isText: Bool { kind == .text }

    /// Top-left origin of a text annotation, mapped into `rect`.
    func textOrigin(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + start.x * rect.width, y: rect.minY + start.y * rect.height)
    }

    func fontSize(in rect: CGRect) -> CGFloat {
        max(1, fontFraction * rect.height)
    }

    /// Measured bounds of a text annotation mapped into `rect` (view or pixel
    /// space), using the same system font as the rasteriser so hit-testing and
    /// the selection border line up with what is drawn.
    func textBounds(in rect: CGRect) -> CGRect {
        let font = UIFont.systemFont(ofSize: fontSize(in: rect))
        let measured = (text.isEmpty ? " " : text) as NSString
        let size = measured.size(withAttributes: [.font: font])
        return CGRect(origin: textOrigin(in: rect), size: size)
    }

    /// A rectangle enclosing the annotation in `rect`, for selection chrome.
    func selectionBounds(in rect: CGRect) -> CGRect {
        if isText { return textBounds(in: rect) }
        let inset = -strokeWidth(in: rect) / 2
        return path(in: rect).boundingBox.insetBy(dx: inset, dy: inset)
    }

    /// Absolute stroke width for a given target rectangle (view or pixel space).
    func strokeWidth(in rect: CGRect) -> CGFloat {
        max(1, widthFraction * min(rect.width, rect.height))
    }

    /// The stroke path mapped into `rect` (the image area in the target space).
    func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
        }

        switch kind {
        case .rectangle:
            path.addRect(boundingRect(map(start), map(end)))
        case .ellipse:
            path.addEllipse(in: boundingRect(map(start), map(end)))
        case .line:
            path.move(to: map(start))
            path.addLine(to: map(end))
        case .arrow:
            addArrow(to: path, from: map(start), to: map(end), in: rect)
        case .freehand:
            guard let first = points.first else { break }
            path.move(to: map(first))
            for point in points.dropFirst() { path.addLine(to: map(point)) }
        case .text:
            break // text is drawn separately, not stroked
        }
        return path
    }

    private func boundingRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func addArrow(to path: CGMutablePath, from a: CGPoint, to b: CGPoint, in rect: CGRect) {
        path.move(to: a)
        path.addLine(to: b)

        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }

        let ux = dx / length
        let uy = dy / length
        let head = min(length * 0.3, 0.06 * min(rect.width, rect.height))
        let angle = CGFloat.pi / 6

        func barb(_ theta: CGFloat) -> CGPoint {
            // Rotate the reversed direction vector by theta, scale by head.
            let vx = -ux * cos(theta) + uy * sin(theta)
            let vy = -ux * sin(theta) - uy * cos(theta)
            return CGPoint(x: b.x + head * vx, y: b.y + head * vy)
        }

        path.move(to: b)
        path.addLine(to: barb(angle))
        path.move(to: b)
        path.addLine(to: barb(-angle))
    }
}

enum AnnotationRasterizer {
    /// Flattens annotations onto the base image at full pixel resolution.
    static func render(_ annotations: [Annotation], onto base: CGImage) -> CGImage? {
        let pixelSize = CGSize(width: base.width, height: base.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)

        let output = renderer.image { context in
            UIImage(cgImage: base).draw(in: CGRect(origin: .zero, size: pixelSize))
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            let fullRect = CGRect(origin: .zero, size: pixelSize)
            for annotation in annotations where !annotation.isHidden {
                if annotation.isText {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: annotation.fontSize(in: fullRect)),
                        .foregroundColor: UIColor(annotation.color)
                    ]
                    (annotation.text as NSString).draw(
                        at: annotation.textOrigin(in: fullRect),
                        withAttributes: attributes
                    )
                    continue
                }
                cg.setStrokeColor(UIColor(annotation.color).cgColor)
                cg.setLineWidth(annotation.strokeWidth(in: fullRect))
                cg.addPath(annotation.path(in: fullRect))
                cg.strokePath()
            }
        }
        return output.cgImage
    }
}
