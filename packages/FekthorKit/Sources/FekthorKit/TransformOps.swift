import Foundation

/// Whole-node transform operations for the Transform panel, all baked into
/// geometry — the shape's outline changes, never a CSS `transform`.
///
/// Contract:
/// - Pure functions; the styled/attributed node is returned with only its
///   geometry replaced.
/// - Skew and distort ALWAYS degrade to `.path` (no primitive can represent
///   a skewed rect or a warped circle): the node is first taken through
///   `Editing2.editable` — primitives expand, an existing `transform`
///   attribute bakes in FIRST (arcs cubicized), then the new map applies.
/// - Skew is affine, so mapping cubic control points is EXACT.
/// - Distort is a bilinear (4-corner) warp: anchor and control points are
///   pushed through the warp individually, so curvature between anchors is
///   approximated (a bilinear map bends straight lines in general, but v1
///   maps endpoints only — flatten-then-refit is deliberately not done).
///   For corner sets that form an affine frame the warp IS that affine map,
///   exactly. Points are mapped in normalized coordinates of `from`, so the
///   four corners of `from` land exactly on the four targets.
/// - `scaledNumeric` / `rotatedNumeric` are thin degree/percent-friendly
///   wrappers over `Editing2.scaled` / `Editing2.rotated`, keeping those
///   ops' primitive-preserving degrade rules.
public enum TransformOps {

    // MARK: - Skew / shear

    /// The matrix for skewX(ax)·skewY(ay) about a fixed point c:
    /// translate(c) · [1 tan(ay) tan(ax) 1 0 0] · translate(-c).
    static func skewTransform(xDegrees: Double, yDegrees: Double, around c: Pt)
        -> TransformValue
    {
        let tx = tan(xDegrees * .pi / 180)
        let ty = tan(yDegrees * .pi / 180)
        let m = [1, ty, tx, 1, -tx * c.y, -ty * c.x]
        return TransformValue(
            raw: "matrix(" + m.map { SVGNum.text($0) }.joined(separator: " ") + ")", matrix: m)
    }

    /// Skew (shear) a node about a fixed point, baked into the outline.
    /// `xDegrees` slants vertical edges (SVG `skewX`), `yDegrees` slants
    /// horizontal edges (`skewY`); the pivot line through `around` stays
    /// put. Always returns a `.path` node; an existing `transform` bakes in
    /// first. A pure shear preserves area (determinant 1 − tan·tan is 1
    /// when only one axis skews).
    public static func skewed(
        _ node: ShapeNode, xDegrees: Double, yDegrees: Double, around c: Pt
    ) -> ShapeNode {
        let t = skewTransform(xDegrees: xDegrees, yDegrees: yDegrees, around: c)
        var out = Editing2.editable(node)
        guard case .path(let paths) = out.kind else { return node }
        out.kind = .path(paths.map { Editing2.bake($0, t) })
        return out
    }

    /// Alias for `skewed` — Illustrator calls the same operation Shear.
    public static func sheared(
        _ node: ShapeNode, xDegrees: Double, yDegrees: Double, around c: Pt
    ) -> ShapeNode {
        skewed(node, xDegrees: xDegrees, yDegrees: yDegrees, around: c)
    }

    // MARK: - Distort (4-corner warp)

    /// Bilinear 4-corner warp: the corners of `bounds` (tl, tr, br, bl in
    /// screen orientation, y down) map EXACTLY to `corners`, everything
    /// else interpolates. Anchor and cubic control points are pushed
    /// through the warp individually — curvature between anchors is an
    /// approximation (exact whenever the corners form an affine frame).
    /// Always returns a `.path` node; an existing `transform` bakes in
    /// first. Degenerate bounds (zero width or height) return the node
    /// unchanged.
    public static func distorted(
        _ node: ShapeNode, corners: (tl: Pt, tr: Pt, br: Pt, bl: Pt),
        from bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)
    ) -> ShapeNode {
        let w = bounds.maxX - bounds.minX
        let h = bounds.maxY - bounds.minY
        guard w > 0, h > 0 else { return node }
        func warp(_ p: Pt) -> Pt {
            let u = (p.x - bounds.minX) / w
            let v = (p.y - bounds.minY) / h
            let a = (1 - u) * (1 - v)
            let b = u * (1 - v)
            let c = u * v
            let d = (1 - u) * v
            return Pt(
                a * corners.tl.x + b * corners.tr.x + c * corners.br.x + d * corners.bl.x,
                a * corners.tl.y + b * corners.tr.y + c * corners.br.y + d * corners.bl.y)
        }
        var out = Editing2.editable(node)
        guard case .path(let paths) = out.kind else { return node }
        out.kind = .path(
            paths.map { rp in
                let cubed = Editing.cubicized(rp)
                var segments: [RefinedSegment] = []
                for seg in cubed.segments {
                    switch seg {
                    case .line(let to):
                        segments.append(.line(to: warp(to)))
                    case .cubic(let c1, let c2, let to):
                        segments.append(.cubic(c1: warp(c1), c2: warp(c2), to: warp(to)))
                    case .arc:
                        break  // unreachable post-cubicize
                    }
                }
                return RefinedPath(start: warp(cubed.start), segments: segments, closed: cubed.closed)
            })
        return out
    }

    // MARK: - Numeric panel wrappers

    /// Scale about a fixed point for the numeric Transform panel — thin
    /// wrapper over `Editing2.scaled` (primitives keep their kind where the
    /// map allows: rect stays rect, circle stays circle under uniform scale).
    public static func scaledNumeric(_ node: ShapeNode, sx: Double, sy: Double, around c: Pt)
        -> ShapeNode
    {
        Editing2.scaled(node, sx: sx, sy: sy, around: c)
    }

    /// Rotate by degrees (positive clockwise on screen, SVG y-down) about a
    /// fixed point — thin wrapper over `Editing2.rotated` (rect/ellipse gain
    /// a `rotate(deg cx cy)` transform, everything else maps points).
    public static func rotatedNumeric(_ node: ShapeNode, degrees: Double, around c: Pt)
        -> ShapeNode
    {
        Editing2.rotated(node, by: degrees * .pi / 180, around: c)
    }
}
