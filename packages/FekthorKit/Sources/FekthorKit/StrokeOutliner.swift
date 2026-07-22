import Foundation

/// Constant-width stroke → fill expansion (the `outline-strokes` export
/// action's geometry core).
///
/// Contract: for each stroked subpath the outline is the stroke's silhouette
/// as the reference renderer draws it — round joins, the shape's linecap
/// (butt / round / square) — built as polygon rings:
/// - open subpath → one closed ring: left offset forward, end cap, right
///   offset backward, start cap;
/// - closed subpath → two closed rings (offset on each side); the second is
///   produced from the reversed centreline, so the pair renders the band
///   correctly under both the even-odd and nonzero fill rules.
///
/// Joins: the convex side gets a round fan around the vertex; the concave
/// side uses the offset-line intersection (miter-clamped at 4× the radius),
/// which keeps the ring simple instead of self-crossing. Curves are flattened
/// adaptively before offsetting; output rings are dense line-segment paths —
/// silhouette correctness over elegance (validated by render comparison, not
/// by node count). Degenerate subpaths (fewer than two distinct points) are
/// skipped.
public enum StrokeOutliner {
    /// Maximum chord deviation when flattening curves, in user units.
    static let flattenTolerance = 0.05
    /// Maximum angular step of round join/cap fans, radians (~14°).
    static let fanStep = 0.25

    // MARK: - Entry

    public static func outline(paths: [RefinedPath], width: Double, cap: LineCap)
        -> [RefinedPath]
    {
        guard width > 0 else { return [] }
        let r = width / 2
        var rings: [RefinedPath] = []
        for rp in paths {
            var pts = flattenAdaptive(rp)
            guard pts.count >= 2 else { continue }
            func push(_ ringPts: [Pt]) {
                if ringPts.count >= 3 { rings.append(ring(ringPts)) }
            }
            if rp.closed {
                // Drop a duplicated seam point, then offset both sides.
                if let f = pts.first, let l = pts.last, dist(f, l) < 1e-9 {
                    pts.removeLast()
                }
                guard pts.count >= 3 else { continue }
                push(offsetClosed(pts, r: r))
                push(offsetClosed(pts.reversed(), r: r))
            } else {
                push(offsetOpen(pts, r: r, cap: cap))
            }
        }
        return rings
    }

    static func ring(_ pts: [Pt]) -> RefinedPath {
        RefinedPath(
            start: pts[0], segments: pts.dropFirst().map { .line(to: $0) }, closed: true)
    }

    // MARK: - Adaptive flattening

    /// Flatten a refined path to a polyline with `flattenTolerance` accuracy:
    /// cubics by recursive subdivision, arcs by sweep-proportional sampling.
    static func flattenAdaptive(_ rp: RefinedPath) -> [Pt] {
        var out: [Pt] = [rp.start]
        var cur = rp.start
        func push(_ p: Pt) {
            if dist(p, out[out.count - 1]) > 1e-9 { out.append(p) }
        }
        for seg in rp.segments {
            switch seg {
            case .line(let to):
                push(to)
                cur = to
            case .cubic(let c1, let c2, let to):
                subdivide(cur, c1, c2, to, depth: 0, push: push)
                push(to)
                cur = to
            case .arc(let c, let radius, let sa, let ea, let cw):
                let sweep = PathRefine.arcSweep(sa, ea, clockwise: cw)
                // Chord error r(1−cos(θ/2)) ≤ tol → θ ≤ 2·acos(1 − tol/r).
                let maxStep =
                    radius > flattenTolerance
                    ? 2 * acos(max(-1, 1 - flattenTolerance / radius)) : .pi / 4
                let steps = max(2, Int(ceil(sweep / max(0.05, maxStep))))
                for s in 1...steps {
                    let t = Double(s) / Double(steps)
                    let ang = cw ? sa + sweep * t : sa - sweep * t
                    push(Pt(c.x + radius * cos(ang), c.y + radius * sin(ang)))
                }
                cur = seg.endPoint
            }
        }
        return out
    }

    static func subdivide(
        _ p0: Pt, _ p1: Pt, _ p2: Pt, _ p3: Pt, depth: Int, push: (Pt) -> Void
    ) {
        // Flat when both control points sit within tolerance of the chord.
        let d1 = segDistance(p1, p0, p3)
        let d2 = segDistance(p2, p0, p3)
        if (d1 <= flattenTolerance && d2 <= flattenTolerance) || depth >= 16 {
            return
        }
        func mid(_ a: Pt, _ b: Pt) -> Pt { Pt((a.x + b.x) / 2, (a.y + b.y) / 2) }
        let q0 = mid(p0, p1)
        let q1 = mid(p1, p2)
        let q2 = mid(p2, p3)
        let r0 = mid(q0, q1)
        let r1 = mid(q1, q2)
        let m = mid(r0, r1)
        subdivide(p0, q0, r0, m, depth: depth + 1, push: push)
        push(m)
        subdivide(m, r1, q2, p3, depth: depth + 1, push: push)
    }

    // MARK: - Offsetting

    /// Left unit normal of a direction (y-down coordinates).
    static func leftNormal(_ d: Pt) -> Pt { Pt(d.y, -d.x) }

    /// The left-side offset polyline of an open path walked start→end:
    /// first/last points offset straight, interior vertices joined (round fan
    /// on the convex side, clamped intersection on the concave side).
    static func sidePoints(_ pts: [Pt], r: Double) -> [Pt] {
        let n = pts.count
        var dirs: [Pt] = []
        dirs.reserveCapacity(n - 1)
        for i in 0..<(n - 1) {
            dirs.append(normalize(Pt(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y)))
        }
        var out: [Pt] = []
        let n0 = leftNormal(dirs[0])
        out.append(Pt(pts[0].x + n0.x * r, pts[0].y + n0.y * r))
        for i in 1..<(n - 1) {
            join(at: pts[i], from: dirs[i - 1], to: dirs[i], r: r, into: &out)
        }
        let nl = leftNormal(dirs[n - 2])
        out.append(Pt(pts[n - 1].x + nl.x * r, pts[n - 1].y + nl.y * r))
        return out
    }

    /// One closed ring: the left-side offset of a closed centreline (every
    /// vertex is a join, including the seam at index 0).
    static func offsetClosed(_ pts: [Pt], r: Double) -> [Pt] {
        let n = pts.count
        var dirs: [Pt] = []
        dirs.reserveCapacity(n)
        for i in 0..<n {
            let a = pts[i]
            let b = pts[(i + 1) % n]
            dirs.append(normalize(Pt(b.x - a.x, b.y - a.y)))
        }
        var out: [Pt] = []
        for i in 0..<n {
            let prev = dirs[(i - 1 + n) % n]
            join(at: pts[i], from: prev, to: dirs[i], r: r, into: &out)
        }
        return dedupeRing(out)
    }

    /// One closed ring for an open centreline: left side out, cap, right side
    /// back (as the left side of the reversed walk), cap.
    static func offsetOpen(_ pts: [Pt], r: Double, cap: LineCap) -> [Pt] {
        var out = sidePoints(pts, r: r)
        let n = pts.count
        let dEnd = normalize(Pt(pts[n - 1].x - pts[n - 2].x, pts[n - 1].y - pts[n - 2].y))
        capPoints(at: pts[n - 1], dir: dEnd, r: r, cap: cap, into: &out)
        out.append(contentsOf: sidePoints(pts.reversed(), r: r))
        let dStart = normalize(Pt(pts[0].x - pts[1].x, pts[0].y - pts[1].y))
        capPoints(at: pts[0], dir: dStart, r: r, cap: cap, into: &out)
        return dedupeRing(out)
    }

    /// Join at vertex `p` between incoming direction `d0` and outgoing `d1`,
    /// on the left-offset side.
    static func join(at p: Pt, from d0: Pt, to d1: Pt, r: Double, into out: inout [Pt]) {
        let n0 = leftNormal(d0)
        let n1 = leftNormal(d1)
        let cross = d0.x * d1.y - d0.y * d1.x
        let dot = d0.x * d1.x + d0.y * d1.y
        let a = Pt(p.x + n0.x * r, p.y + n0.y * r)
        let b = Pt(p.x + n1.x * r, p.y + n1.y * r)
        if abs(cross) < 1e-9 && dot >= 0 {
            out.append(a)  // collinear continuation
            return
        }
        if cross > 0 {
            // Left side is outside the turn: round fan from n0 to n1.
            let a0 = atan2(n0.y, n0.x)
            var delta = atan2(n1.y, n1.x) - a0
            while delta <= -Double.pi { delta += 2 * .pi }
            while delta > Double.pi { delta -= 2 * .pi }
            let steps = max(1, Int(ceil(abs(delta) / fanStep)))
            for k in 0...steps {
                let ang = a0 + delta * Double(k) / Double(steps)
                out.append(Pt(p.x + r * cos(ang), p.y + r * sin(ang)))
            }
            return
        }
        // Left side is inside the turn: intersect the two offset lines
        // (A + t·d0 = B + u·d1); clamp runaway miters near 180° turns.
        let denom = cross
        if abs(denom) > 1e-12 {
            let t = ((b.x - a.x) * d1.y - (b.y - a.y) * d1.x) / denom
            let x = Pt(a.x + d0.x * t, a.y + d0.y * t)
            if dist(x, p) <= 4 * r {
                out.append(x)
                return
            }
        }
        out.append(a)
        out.append(b)
    }

    /// Cap at endpoint `p` facing direction `dir` (pointing outward, away
    /// from the path). Connects the left offset of the arriving walk to the
    /// left offset of the departing reversed walk.
    static func capPoints(at p: Pt, dir: Pt, r: Double, cap: LineCap, into out: inout [Pt]) {
        let n = leftNormal(dir)
        switch cap {
        case .butt:
            break  // straight connection
        case .round:
            // Semicircle from +n to −n, bulging through `dir`.
            let a0 = atan2(n.y, n.x)
            let steps = max(2, Int(ceil(Double.pi / fanStep)))
            for k in 1..<steps {
                let ang = a0 + .pi * Double(k) / Double(steps)
                out.append(Pt(p.x + r * cos(ang), p.y + r * sin(ang)))
            }
        case .square:
            out.append(Pt(p.x + n.x * r + dir.x * r, p.y + n.y * r + dir.y * r))
            out.append(Pt(p.x - n.x * r + dir.x * r, p.y - n.y * r + dir.y * r))
        }
    }

    // MARK: - Small helpers

    static func dedupeRing(_ pts: [Pt]) -> [Pt] {
        var out = PathRefine.dedupe(pts)
        if out.count > 1, dist(out[0], out[out.count - 1]) < 1e-9 {
            out.removeLast()
        }
        return out
    }

    static func normalize(_ v: Pt) -> Pt { PathRefine.normalize(v) }
    static func dist(_ a: Pt, _ b: Pt) -> Double { PathRefine.dist(a, b) }
    static func segDistance(_ p: Pt, _ a: Pt, _ b: Pt) -> Double { PathRefine.segDist(p, a, b) }
}
