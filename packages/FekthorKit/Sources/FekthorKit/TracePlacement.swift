import Foundation

/// Placing a traced document inside another document.
///
/// Vectorize traces a placed raster on its own pixel grid (the trace pipeline
/// works at up to 2048px), then the result has to land exactly where the image
/// sat — a 24pt icon artboard, say. Everything is BAKED: geometry, stroke
/// widths and gradient coordinates are mapped into the target rect, so the
/// swapped-in vectors carry no wrapper transform and read like hand-drawn
/// nodes (docs/fekthor/EDITOR-PLAN.md: transforms bake, never accumulate).
public enum TracePlacement {
    /// The traced document's nodes mapped into `rect` (target-document
    /// coordinates), with ids renumbered from `firstID` in document order.
    /// A degenerate source viewBox or target rect yields no nodes.
    public static func nodes(
        of traced: GraphicDocument,
        into rect: (x: Double, y: Double, width: Double, height: Double),
        firstID: Int
    ) -> [GraphicNode] {
        let vb = traced.viewBox
        guard vb.width > 0, vb.height > 0, rect.width > 0, rect.height > 0 else { return [] }
        let sx = rect.width / vb.width
        let sy = rect.height / vb.height
        // Scale about the origin, then shift the scaled viewBox origin onto
        // the target rect: p → (sx·x + dx, sy·y + dy).
        let dx = rect.x - sx * vb.minX
        let dy = rect.y - sy * vb.minY
        // Widths and radii are one-dimensional: a non-uniform placement uses
        // the geometric mean, which is what Illustrator's "scale strokes" does.
        let linear = (abs(sx) * abs(sy)).squareRoot()
        var next = firstID
        return traced.nodes.map { mapped($0, sx, sy, dx, dy, linear, &next) }
    }

    static func mapped(
        _ node: GraphicNode, _ sx: Double, _ sy: Double, _ dx: Double, _ dy: Double,
        _ linear: Double, _ next: inout Int
    ) -> GraphicNode {
        switch node {
        case .shape(var s):
            s = Editing2.scaled(s, sx: sx, sy: sy, around: Pt(0, 0))
            s = Editing2.translated(s, dx: dx, dy: dy)
            s.style = scaledStyle(s.style, sx, sy, dx, dy, linear)
            s.id = next
            next += 1
            return .shape(s)
        case .image(var i):
            i = i.scaled(sx: sx, sy: sy, around: Pt(0, 0)).translated(dx: dx, dy: dy)
            i.id = next
            next += 1
            return .image(i)
        case .group(var g):
            g.id = next
            next += 1
            if g.transform == nil {
                g.children = g.children.map {
                    mapped($0, sx, sy, dx, dy, linear, &next)
                }
            } else {
                // A group that already carries a transform keeps its children
                // untouched; the placement composes onto its own matrix.
                g.transform = TransformValue.composed(
                    ImageNode.matrixTransform([sx, 0, 0, sy, dx, dy]), g.transform)
            }
            return .group(g)
        case .raw(var r):
            r.id = next
            next += 1
            return .raw(r)
        }
    }

    /// Stroke width and gradient geometry follow the placement: both are
    /// expressed in user space, so leaving them alone would give hairlines on
    /// a shrunken trace and gradients anchored off-shape.
    static func scaledStyle(
        _ style: Style, _ sx: Double, _ sy: Double, _ dx: Double, _ dy: Double, _ linear: Double
    ) -> Style {
        var out = style
        if case .number(let w, let unit)? = style.value(of: "stroke-width") {
            out.set("stroke-width", .number(w * linear, unit: unit))
        }
        for name in ["fill", "stroke"] {
            guard case .paint(let paint)? = style.value(of: name) else { continue }
            out.set(name, .paint(scaledPaint(paint, sx, sy, dx, dy, linear)))
        }
        return out
    }

    static func scaledPaint(
        _ paint: PaintValue, _ sx: Double, _ sy: Double, _ dx: Double, _ dy: Double,
        _ linear: Double
    ) -> PaintValue {
        func map(_ p: Pt) -> Pt { Pt(sx * p.x + dx, sy * p.y + dy) }
        switch paint {
        case .linear(let g):
            return .linear(LinearGradient(p0: map(g.p0), p1: map(g.p1), stops: g.stops))
        case .radial(let g):
            return .radial(
                RadialGradient(center: map(g.center), radius: g.radius * linear, stops: g.stops))
        default:
            return paint
        }
    }
}
