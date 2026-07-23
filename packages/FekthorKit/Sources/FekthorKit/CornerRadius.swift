import Foundation

/// Per-corner rounded-rectangle authoring. Uniform rounding stays a native
/// `.rect` (rx/ry round-trip through SVG); the moment the four corners
/// decouple there is no rect form left, so the editor rebuilds the outline
/// as a `.path` through this builder. The corner geometry is the same
/// kappa-cubic quarter round `Editing2.pathify` uses for a uniform-radius
/// rect — with all four radii equal the two produce identical paths.
public enum CornerRadius {
    /// The outline of a rectangle with independent corner radii: clockwise
    /// from the end of the top-left corner, one line per edge and one cubic
    /// per rounded corner (sharp corners emit no cubic). Radii are clamped
    /// CSS-style — negatives to zero, then all four scaled by one common
    /// factor so no side's adjacent radii overlap.
    public static func roundedRectPath(
        x: Double, y: Double, width: Double, height: Double,
        topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double
    ) -> RefinedPath {
        let (tl, tr, br, bl) = clamped(
            width: width, height: height,
            topLeft: topLeft, topRight: topRight,
            bottomRight: bottomRight, bottomLeft: bottomLeft)
        let k = Editing2.kappa
        let eps = 0.001
        var segments: [RefinedSegment] = []
        // Top edge, then clockwise. The start sits at the top-left corner's
        // end, exactly like the uniform rect in `Editing2.pathify`.
        segments.append(.line(to: Pt(x + width - tr, y)))
        if tr > eps {
            segments.append(
                .cubic(
                    c1: Pt(x + width - tr + k * tr, y), c2: Pt(x + width, y + tr - k * tr),
                    to: Pt(x + width, y + tr)))
        }
        segments.append(.line(to: Pt(x + width, y + height - br)))
        if br > eps {
            segments.append(
                .cubic(
                    c1: Pt(x + width, y + height - br + k * br),
                    c2: Pt(x + width - br + k * br, y + height),
                    to: Pt(x + width - br, y + height)))
        }
        segments.append(.line(to: Pt(x + bl, y + height)))
        if bl > eps {
            segments.append(
                .cubic(
                    c1: Pt(x + bl - k * bl, y + height), c2: Pt(x, y + height - bl + k * bl),
                    to: Pt(x, y + height - bl)))
        }
        segments.append(.line(to: Pt(x, y + tl)))
        if tl > eps {
            segments.append(
                .cubic(c1: Pt(x, y + tl - k * tl), c2: Pt(x + tl - k * tl, y), to: Pt(x + tl, y)))
        }
        return RefinedPath(start: Pt(x + tl, y), segments: segments, closed: true)
    }

    /// CSS's border-radius overlap rule: after flooring negatives at zero,
    /// find the largest factor `f ≤ 1` with `f · (rA + rB) ≤ side` for every
    /// side's adjacent pair, and scale ALL four radii by it — proportional
    /// reduction, so corners keep their relative weights and adjacent
    /// rounds never overlap.
    static func clamped(
        width: Double, height: Double,
        topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double
    ) -> (tl: Double, tr: Double, br: Double, bl: Double) {
        let tl = max(0, topLeft)
        let tr = max(0, topRight)
        let br = max(0, bottomRight)
        let bl = max(0, bottomLeft)
        var f = 1.0
        for (side, pair) in [
            (width, tl + tr), (width, bl + br), (height, tl + bl), (height, tr + br),
        ] where pair > side {
            f = Swift.min(f, side / pair)
        }
        return (tl * f, tr * f, br * f, bl * f)
    }
}
