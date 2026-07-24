import Foundation

/// Corner rounding on arbitrary paths (Corners palette + canvas corner
/// dots). A CORNER anchor joins two segments whose tangents differ by more
/// than ~15°; v1 fillets line-line corners (the dominant case for icon
/// work — polygons, polylines, expanded rects, pen paths). Anchors touching
/// a curve are left alone, as are near-collinear anchors and open-path
/// endpoints. The fillet is the standard kappa-cubic arc approximation,
/// clamped per corner to half the shorter adjacent segment length so two
/// fillets on one edge can never overlap (CSS border-radius style).
///
/// Like Illustrator before live corners, the edit is destructive: the
/// rounded path replaces the original and nothing is stored.
public enum LiveCorners {
    /// Corners sharper than this are filleted; flatter anchors are treated
    /// as smooth points and skipped (radians; ~15°).
    public static let cornerThreshold = 15.0 * Double.pi / 180

    /// One fillet-able anchor of a path: its pathAnchors index, position,
    /// the interior bisector (unit vector pointing into the wedge between
    /// the two edges — where the fillet arc's centre lies) and the turn
    /// angle between the edge tangents (radians, 0 = straight).
    public struct CornerInfo: Equatable, Sendable {
        public var index: Int
        public var position: Pt
        public var bisector: Pt
        public var turnAngle: Double
    }

    // MARK: - Ring model

    /// A subpath reduced to its anchor ring: unique anchors plus one edge
    /// per anchor pair (closed) or per gap (open). Edges keep their source
    /// segment so curves re-emit verbatim.
    private struct Ring {
        var anchors: [Pt]
        /// edges[i] connects anchors[i] → anchors[(i+1) % count] (closed)
        /// or anchors[i] → anchors[i+1] (open). nil segment = the implicit
        /// closing line of a closed path with no explicit final segment.
        var edges: [RefinedSegment?]
        var closed: Bool
    }

    private static func ring(of rp: RefinedPath) -> Ring? {
        // Arcs cubicize first so only lines/cubics remain (fillets only land
        // between lines; curves pass through untouched).
        let path = Editing.cubicized(rp)
        guard !path.segments.isEmpty else { return nil }
        var anchors: [Pt] = [path.start]
        var edges: [RefinedSegment?] = []
        for seg in path.segments {
            anchors.append(seg.endPoint)
            edges.append(seg)
        }
        if path.closed {
            let last = anchors[anchors.count - 1]
            let dx = last.x - path.start.x
            let dy = last.y - path.start.y
            if dx * dx + dy * dy < 0.25 {
                // Explicit closing segment: its end IS the start anchor.
                anchors.removeLast()
            } else {
                // Implicit closure: a synthetic closing line back to start.
                edges.append(nil)
            }
        }
        guard anchors.count >= (path.closed ? 3 : 2) else { return nil }
        return Ring(anchors: anchors, edges: edges, closed: path.closed)
    }

    private static func isLine(_ seg: RefinedSegment?) -> Bool {
        switch seg {
        case nil: return true  // implicit closing line
        case .line: return true
        default: return false
        }
    }

    private static func unit(from a: Pt, to b: Pt) -> Pt? {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 1e-9 else { return nil }
        return Pt(dx / len, dy / len)
    }

    private static func length(from a: Pt, to b: Pt) -> Double {
        ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
    }

    /// The corner geometry at ring position `i`, or nil when the anchor is
    /// not a fillet-able line-line corner (curve neighbour, near-collinear,
    /// degenerate edge, open endpoint).
    private static func cornerAt(_ ring: Ring, _ i: Int)
        -> (uIn: Pt, uOut: Pt, lIn: Double, lOut: Double, turn: Double)?
    {
        let n = ring.anchors.count
        let prevEdge: Int
        let nextEdge: Int
        if ring.closed {
            prevEdge = (i + n - 1) % n
            nextEdge = i
        } else {
            guard i > 0, i < n - 1 else { return nil }
            prevEdge = i - 1
            nextEdge = i
        }
        guard isLine(ring.edges[prevEdge]), isLine(ring.edges[nextEdge]) else { return nil }
        let prev = ring.anchors[ring.closed ? (i + n - 1) % n : i - 1]
        let here = ring.anchors[i]
        let next = ring.anchors[ring.closed ? (i + 1) % n : i + 1]
        guard let uIn = unit(from: prev, to: here), let uOut = unit(from: here, to: next)
        else { return nil }
        let dot = max(-1, min(1, uIn.x * uOut.x + uIn.y * uOut.y))
        let turn = acos(dot)
        guard turn > cornerThreshold, turn < Double.pi - 1e-6 else { return nil }
        return (uIn, uOut, length(from: prev, to: here), length(from: here, to: next), turn)
    }

    // MARK: - Public API

    /// Every fillet-able corner anchor of the path, with position and
    /// interior bisector — the canvas draws its corner dots from this.
    /// Indices follow the `Editing.pathAnchors` convention (0 = start,
    /// i+1 = end of segment i, closed seam deduped onto 0).
    public static func cornerAnchors(of rp: RefinedPath) -> [CornerInfo] {
        guard let ring = ring(of: rp) else { return [] }
        var out: [CornerInfo] = []
        for i in ring.anchors.indices {
            guard let c = cornerAt(ring, i) else { continue }
            let bx = c.uOut.x - c.uIn.x
            let by = c.uOut.y - c.uIn.y
            let blen = (bx * bx + by * by).squareRoot()
            guard blen > 1e-9 else { continue }
            out.append(
                CornerInfo(
                    index: i, position: ring.anchors[i],
                    bisector: Pt(bx / blen, by / blen), turnAngle: c.turn))
        }
        return out
    }

    /// The path with each corner anchor replaced by a kappa-cubic fillet of
    /// `radius`. `corners` limits the edit to those anchor indices (in the
    /// `pathAnchors` convention); nil rounds every corner. Radii are
    /// clamped per corner so the trim never eats more than half of either
    /// adjacent segment. Non-corner anchors and curved segments pass
    /// through untouched; radius ≤ 0 returns the path unchanged.
    public static func rounded(
        path rp: RefinedPath, radius: Double, corners: Set<Int>? = nil
    ) -> RefinedPath {
        guard radius > 1e-9 else { return rp }
        return rounded(path: rp) { i in (corners?.contains(i) ?? true) ? radius : 0 }
    }

    /// The path with each corner anchor filleted by its OWN radius (keyed by
    /// the `pathAnchors` index). Anchors with no entry — or radius ≤ 0 — stay
    /// sharp. This is what `RefinedPath.flattenedCorners` calls.
    public static func rounded(path rp: RefinedPath, radii: [Int: Double]) -> RefinedPath {
        guard radii.values.contains(where: { $0 > 1e-9 }) else { return rp }
        return rounded(path: rp) { radii[$0] ?? 0 }
    }

    private struct Fillet {
        var p1: Pt  // tangency on the incoming edge
        var c1: Pt
        var c2: Pt
        var p2: Pt  // tangency on the outgoing edge
    }

    /// Shared core: fillet each corner by the radius `radiusAt` returns for it.
    private static func rounded(
        path rp: RefinedPath, radiusAt: (Int) -> Double
    ) -> RefinedPath {
        guard let ring = ring(of: rp) else { return rp }
        let n = ring.anchors.count

        var fillets: [Int: Fillet] = [:]
        for i in ring.anchors.indices {
            let radius = radiusAt(i)
            guard radius > 1e-9, let c = cornerAt(ring, i) else { continue }
            // Tangent length for radius r at turn angle φ: t = r·tan(φ/2),
            // clamped to half of each adjacent edge (shared edges stay safe).
            var t = radius * tan(c.turn / 2)
            t = min(t, c.lIn / 2, c.lOut / 2)
            guard t > 1e-9 else { continue }
            let rEff = t / tan(c.turn / 2)
            // Cubic arc approximation: control distance (4/3)·tan(φ/4)·r.
            let d = (4.0 / 3.0) * tan(c.turn / 4) * rEff
            let here = ring.anchors[i]
            let p1 = Pt(here.x - t * c.uIn.x, here.y - t * c.uIn.y)
            let p2 = Pt(here.x + t * c.uOut.x, here.y + t * c.uOut.y)
            fillets[i] = Fillet(
                p1: p1,
                c1: Pt(p1.x + d * c.uIn.x, p1.y + d * c.uIn.y),
                c2: Pt(p2.x - d * c.uOut.x, p2.y - d * c.uOut.y),
                p2: p2)
        }
        guard !fillets.isEmpty else { return rp }

        // Rebuild: walk the edges; a filleted anchor contributes its arc in
        // place of the sharp point. The start moves onto fillet 0's exit
        // when the seam itself is rounded.
        var start = ring.anchors[0]
        var segments: [RefinedSegment] = []
        if ring.closed, let f0 = fillets[0] { start = f0.p2 }

        func emitEdge(_ index: Int, endAnchor: Int) {
            let edge = ring.edges[index]
            let target = fillets[endAnchor]?.p1 ?? ring.anchors[endAnchor]
            switch edge {
            case .cubic(let c1, let c2, let to):
                segments.append(.cubic(c1: c1, c2: c2, to: to))
            case nil, .line:
                segments.append(.line(to: target))
            case .arc:
                break  // unreachable: ring() cubicizes arcs
            }
            if let f = fillets[endAnchor] {
                segments.append(.cubic(c1: f.c1, c2: f.c2, to: f.p2))
            }
        }

        if ring.closed {
            for i in 0..<n {
                emitEdge(i, endAnchor: (i + 1) % n)
            }
        } else {
            for i in 0..<(n - 1) {
                emitEdge(i, endAnchor: i + 1)
            }
        }
        // The rebuilt geometry is the baked form — it carries no live radii.
        return RefinedPath(start: start, segments: segments, closed: ring.closed)
    }
}
