import CoreGraphics
import Foundation
import SwiftUI
import UIKit

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
    /// PostScript/family name of the font; nil = system font.
    var fontName: String?
    /// Shared stack order across layers and annotations (higher = on top).
    var z: Double = 0
    /// Hidden layers stay in the stack but are skipped by the editor canvas
    /// and the rasteriser (toggled from the Layers panel's eye button).
    var isHidden = false
    /// The brush behind a freehand stroke (nil for shapes and text). Names the
    /// stroke's layer and sets its cap style; opacity/softness are copied onto
    /// the stroke so slider tweaks after picking a preset still land per stroke.
    var brush: BrushPreset?
    /// Stroke opacity, applied to the composited stroke as a whole so
    /// overlapping pressure segments never double-darken.
    var opacity: CGFloat = 1
    /// Soft-edge amount 0…1; the blur radius scales with the stroke width.
    var softness: CGFloat = 0
    /// Per-point width multipliers from Apple Pencil pressure, parallel to
    /// `points`. Empty (or all ~1) renders as a uniform stroke.
    var pressureWidths: [CGFloat] = []

    var isText: Bool { kind == .text }

    /// Highlighter strokes render with flat (butt) caps.
    var flatCaps: Bool { brush?.flatCaps ?? false }

    /// Layer name: the brush name for brush strokes, the tool name otherwise.
    var displayLabel: String {
        if kind == .freehand, let brush { return brush.label }
        return kind.label
    }

    /// Gaussian radius for the soft edge in a given target rectangle.
    func blurRadius(in rect: CGRect) -> CGFloat {
        guard softness > 0 else { return 0 }
        return softness * strokeWidth(in: rect) * 0.6
    }

    /// Whether the stroke renders as pressure-varied segments (freehand with
    /// recorded pencil force that actually deviates from the base width).
    var hasVariableWidth: Bool {
        kind == .freehand && !flatCaps
            && points.count > 1 && pressureWidths.count == points.count
            && pressureWidths.contains { abs($0 - 1) > 0.01 }
    }

    /// One short stroked path per freehand segment, each with its own width
    /// (the average of its endpoints' pressure multipliers). Round caps make
    /// consecutive segments join seamlessly.
    func segmentPaths(in rect: CGRect) -> [(path: CGPath, width: CGFloat)] {
        guard points.count > 1, pressureWidths.count == points.count else { return [] }
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
        }
        let base = strokeWidth(in: rect)
        var segments: [(path: CGPath, width: CGFloat)] = []
        for index in 1..<points.count {
            let segment = CGMutablePath()
            segment.move(to: map(points[index - 1]))
            segment.addLine(to: map(points[index]))
            let width = base * (pressureWidths[index - 1] + pressureWidths[index]) / 2
            segments.append((segment, max(0.5, width)))
        }
        return segments
    }

    /// SwiftUI font for the editor preview at the given target rect.
    func swiftUIFont(in rect: CGRect) -> Font {
        let size = fontSize(in: rect)
        if let fontName { return .custom(fontName, size: size) }
        return .system(size: size)
    }

    /// UIFont for full-resolution rasterisation at the given target rect.
    func uiFont(in rect: CGRect) -> UIFont {
        let size = fontSize(in: rect)
        if let fontName, let font = UIFont(name: fontName, size: size) { return font }
        return .systemFont(ofSize: size)
    }

    /// A copy shifted by a normalised (0…1) delta — moves every point so the
    /// whole annotation (text origin, shape endpoints, freehand path) translates.
    func translated(dx: CGFloat, dy: CGFloat) -> Annotation {
        var copy = self
        copy.start = CGPoint(x: start.x + dx, y: start.y + dy)
        copy.end = CGPoint(x: end.x + dx, y: end.y + dy)
        copy.points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return copy
    }

    /// A generous hit rectangle (view space) for selecting/moving the annotation
    /// by touch — padded so thin strokes and text are easy to grab.
    func hitBounds(in rect: CGRect) -> CGRect {
        if isText {
            let fs = fontSize(in: rect)
            let origin = textOrigin(in: rect)
            let width = max(CGFloat(text.count) * fs * 0.62, fs)
            return CGRect(x: origin.x, y: origin.y, width: width, height: fs * 1.25)
                .insetBy(dx: -14, dy: -14)
        }
        let box = path(in: rect).boundingBoxOfPath
        guard !box.isNull, !box.isInfinite else { return .null }
        let pad = max(strokeWidth(in: rect), 22)
        return box.insetBy(dx: -pad, dy: -pad)
    }

    /// Top-left origin of a text annotation, mapped into `rect`.
    func textOrigin(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + start.x * rect.width, y: rect.minY + start.y * rect.height)
    }

    func fontSize(in rect: CGRect) -> CGFloat {
        max(1, fontFraction * rect.height)
    }

    /// Measured bounds of a text annotation mapped into `rect` (view or pixel
    /// space), using the same font as the rasteriser so hit-testing and
    /// the selection border line up with what is drawn.
    func textBounds(in rect: CGRect) -> CGRect {
        let font = uiFont(in: rect)
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
            let fullRect = CGRect(origin: .zero, size: pixelSize)
            for annotation in annotations { draw(annotation, in: cg, fullRect: fullRect) }
        }
        return output.cgImage
    }

    /// Draw a single annotation into an existing context (used for the unified
    /// layer/annotation stack, so they can be interleaved by depth). Hidden
    /// annotations are skipped; strokes carry their brush opacity, softness,
    /// caps, and pressure widths.
    static func draw(_ annotation: Annotation, in cg: CGContext, fullRect: CGRect) {
        guard !annotation.isHidden else { return }
        if annotation.isText {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: annotation.uiFont(in: fullRect),
                .foregroundColor: UIColor(annotation.color)
            ]
            (annotation.text as NSString).draw(
                at: annotation.textOrigin(in: fullRect),
                withAttributes: attributes
            )
            return
        }
        drawStroke(annotation, into: cg, pixelSize: fullRect.size)
    }

    /// Strokes one annotation with its opacity, softness, caps, and pressure
    /// widths. Soft strokes are rendered offscreen at full alpha, blurred
    /// once, and composited with the stroke's opacity so the feathered edge
    /// and the translucency read exactly like the live Canvas preview.
    private static func drawStroke(_ annotation: Annotation, into cg: CGContext, pixelSize: CGSize) {
        let fullRect = CGRect(origin: .zero, size: pixelSize)

        if annotation.softness > 0 {
            guard let strokeImage = annotation.softStrokeImage(pixelSize: pixelSize) else { return }
            UIImage(cgImage: strokeImage).draw(in: fullRect, blendMode: .normal, alpha: annotation.opacity)
            return
        }

        cg.saveGState()
        cg.setAlpha(annotation.opacity)
        cg.setStrokeColor(UIColor(annotation.color).cgColor)
        cg.setLineCap(annotation.flatCaps ? .butt : .round)
        cg.setLineJoin(.round)
        if annotation.hasVariableWidth {
            // Full-alpha segments inside a transparency layer, composited once
            // with the stroke's opacity, so overlaps never darken.
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            for segment in annotation.segmentPaths(in: fullRect) {
                cg.setLineWidth(segment.width)
                cg.addPath(segment.path)
                cg.strokePath()
            }
            cg.endTransparencyLayer()
        } else {
            cg.setLineWidth(annotation.strokeWidth(in: fullRect))
            cg.addPath(annotation.path(in: fullRect))
            cg.strokePath()
        }
        cg.restoreGState()
    }
}

extension Annotation {
    /// The stroke alone at full alpha, feathered when soft — the rasteriser
    /// composites this once with the stroke's opacity.
    func softStrokeImage(pixelSize: CGSize) -> CGImage? {
        let fullRect = CGRect(origin: .zero, size: pixelSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: pixelSize, format: format).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(UIColor(color).cgColor)
            cg.setLineCap(flatCaps ? .butt : .round)
            cg.setLineJoin(.round)
            if hasVariableWidth {
                for segment in segmentPaths(in: fullRect) {
                    cg.setLineWidth(segment.width)
                    cg.addPath(segment.path)
                    cg.strokePath()
                }
            } else {
                cg.setLineWidth(strokeWidth(in: fullRect))
                cg.addPath(path(in: fullRect))
                cg.strokePath()
            }
        }
        guard let cgImage = rendered.cgImage else { return nil }
        return StrokeSoftener.blurred(cgImage, radius: blurRadius(in: fullRect))
    }
}

extension GraphicsContext {
    /// Live-preview twin of the rasteriser's stroke pass: the stroke is built
    /// at full alpha inside a layer, then the layer is composited once with
    /// the stroke's opacity and blur, so pressure segments and soft edges look
    /// the same on screen as in the flattened image.
    func drawStroke(_ annotation: Annotation, in rect: CGRect) {
        var context = self
        context.opacity *= Double(annotation.opacity)
        if annotation.softness > 0 {
            context.addFilter(.blur(radius: annotation.blurRadius(in: rect)))
        }
        let shading = GraphicsContext.Shading.color(annotation.color)
        context.drawLayer { layer in
            if annotation.hasVariableWidth {
                for segment in annotation.segmentPaths(in: rect) {
                    layer.stroke(
                        Path(segment.path),
                        with: shading,
                        style: StrokeStyle(lineWidth: segment.width, lineCap: .round, lineJoin: .round)
                    )
                }
            } else {
                layer.stroke(
                    Path(annotation.path(in: rect)),
                    with: shading,
                    style: StrokeStyle(
                        lineWidth: annotation.strokeWidth(in: rect),
                        lineCap: annotation.flatCaps ? .butt : .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }
}
