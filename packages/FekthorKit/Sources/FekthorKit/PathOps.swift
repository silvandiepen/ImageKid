import Foundation

/// Pure path operations on Document Model v2 geometry: adaptive flattening,
/// boolean combination (union / subtract / intersect / exclude), simplify and
/// join. Deterministic — no randomness and no dictionary-order dependence.
///
/// v1 documented choice: boolean results are emitted as closed line-segment
/// polygons (flattened at `defaultTolerance`), not refitted curves —
/// silhouette correctness over elegance. Results render identically under
/// either fill rule; the combined node declares `fill-rule: evenodd`.
public enum PathOps {
    /// Default flattening tolerance in px: maximum chord deviation when
    /// subdividing cubics (by flatness) and arcs (by chord-error angle step).
    public static let defaultTolerance = 0.25

    // MARK: - Flattening

    /// Flatten a refined path to a polyline within `tolerance` px: lines pass
    /// through, cubics subdivide recursively until both control points sit
    /// within tolerance of the chord, arcs step by the angle whose chord
    /// error stays under tolerance. Open paths flatten to open polylines.
    public static func flattened(_ path: RefinedPath, tolerance: Double = defaultTolerance)
        -> [Pt]
    {
        let tol = max(tolerance, 1e-4)
        var out: [Pt] = [path.start]
        var cur = path.start
        func push(_ p: Pt) {
            let last = out[out.count - 1]
            if (p.x - last.x) * (p.x - last.x) + (p.y - last.y) * (p.y - last.y) > 1e-18 {
                out.append(p)
            }
        }
        for seg in path.segments {
            switch seg {
            case .line(let to):
                push(to)
                cur = to
            case .cubic(let c1, let c2, let to):
                subdivideCubic(cur, c1, c2, to, tolerance: tol, depth: 0, push: push)
                push(to)
                cur = to
            case .arc(let c, let radius, let sa, let ea, let cw):
                var sweep = cw ? ea - sa : sa - ea
                while sweep < 0 { sweep += 2 * .pi }
                while sweep >= 2 * .pi { sweep -= 2 * .pi }
                // Chord error r(1−cos(θ/2)) ≤ tol → θ ≤ 2·acos(1 − tol/r).
                let maxStep =
                    radius > tol ? 2 * acos(max(-1, 1 - tol / radius)) : .pi / 4
                let steps = max(2, Int(ceil(sweep / max(0.01, maxStep))))
                for s in 1...steps {
                    let t = Double(s) / Double(steps)
                    let ang = cw ? sa + sweep * t : sa - sweep * t
                    push(Pt(c.x + radius * cos(ang), c.y + radius * sin(ang)))
                }
                cur = seg.endPoint
            }
        }
        // A closed path's implicit (or explicit) seam: drop a duplicated
        // closing point so rings never repeat their start vertex.
        if path.closed, out.count > 1 {
            let first = out[0]
            let last = out[out.count - 1]
            if abs(first.x - last.x) < 1e-9, abs(first.y - last.y) < 1e-9 {
                out.removeLast()
            }
        }
        return out
    }

    static func subdivideCubic(
        _ p0: Pt, _ p1: Pt, _ p2: Pt, _ p3: Pt, tolerance: Double, depth: Int,
        push: (Pt) -> Void
    ) {
        // Flat when both control points sit within tolerance of the chord.
        if (perpToChord(p1, p0, p3) <= tolerance && perpToChord(p2, p0, p3) <= tolerance)
            || depth >= 18
        {
            return
        }
        func mid(_ a: Pt, _ b: Pt) -> Pt { Pt((a.x + b.x) / 2, (a.y + b.y) / 2) }
        let q0 = mid(p0, p1)
        let q1 = mid(p1, p2)
        let q2 = mid(p2, p3)
        let r0 = mid(q0, q1)
        let r1 = mid(q1, q2)
        let m = mid(r0, r1)
        subdivideCubic(p0, q0, r0, m, tolerance: tolerance, depth: depth + 1, push: push)
        push(m)
        subdivideCubic(m, r1, q2, p3, tolerance: tolerance, depth: depth + 1, push: push)
    }

    static func perpToChord(_ p: Pt, _ a: Pt, _ b: Pt) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        if len < 1e-12 {
            let ex = p.x - a.x
            let ey = p.y - a.y
            return (ex * ex + ey * ey).squareRoot()
        }
        return abs((p.x - a.x) * dy - (p.y - a.y) * dx) / len
    }

    /// Flatten closed subpaths to polygon rings for boolean input. Throws
    /// `PathOpsError.openSubpath` for any open subpath — booleans operate on
    /// regions only. Degenerate (< 3 vertex) rings are dropped silently.
    public static func rings(of paths: [RefinedPath], tolerance: Double = defaultTolerance)
        throws -> [[Pt]]
    {
        var out: [[Pt]] = []
        for (i, path) in paths.enumerated() {
            guard path.closed else { throw PathOpsError.openSubpath(index: i) }
            let ring = flattened(path, tolerance: tolerance)
            if ring.count >= 3 { out.append(ring) }
        }
        return out
    }

    // MARK: - Boolean core (ring level)

    /// Apply a boolean operation to two multi-ring regions. Each input is
    /// interpreted under its own fill rule; the result is a clean even-odd
    /// boundary (outer rings positive shoelace area, holes negative, no
    /// overlapping rings). Handles shared edges, vertex-on-edge touches and
    /// identical inputs exactly (coordinates snap to a 1e-7 grid).
    public static func clip(
        subject: [[Pt]], subjectRule: FillRule = .evenOdd,
        clip clipRings: [[Pt]], clipRule: FillRule = .evenOdd, op: BoolOp
    ) -> [[Pt]] {
        PolygonOverlay.clip(
            subject: subject, subjectRule: subjectRule, clip: clipRings, clipRule: clipRule,
            op: op)
    }

    /// Signed area of a multi-ring region boundary as produced by `clip`
    /// (outer rings positive, holes negative — the sum is the region area).
    public static func regionArea(_ rings: [[Pt]]) -> Double {
        rings.reduce(0) { $0 + Geometry.signedArea($1) }
    }

    // MARK: - Node-level API

    /// The node's fill rule as SVG resolves it (`nonzero` unless the
    /// effective style declares `fill-rule: evenodd`).
    public static func fillRule(of node: ShapeNode) -> FillRule {
        if case .keyword(let k)? = node.effectiveStyle.value(of: "fill-rule"),
            k.lowercased() == "evenodd"
        {
            return .evenOdd
        }
        return .nonZero
    }

    /// Combine nodes with a boolean operation, left-fold in document order
    /// (first = subject). Each node is baked via `Editing2.bakedPaths`
    /// (primitives expanded, transforms applied) and flattened; the result
    /// adopts the FIRST node's style, attributes and id, becomes `.path`
    /// polygons, and declares `fill-rule: evenodd`. A single node is
    /// normalized (self-overlaps resolved under its own rule).
    ///
    /// Returns nil when `nodes` is empty, when any subpath is open, or when
    /// the result region is empty (e.g. intersecting disjoint shapes).
    public static func combine(
        _ nodes: [ShapeNode], op: BoolOp, tolerance: Double = defaultTolerance
    ) -> ShapeNode? {
        guard let first = nodes.first else { return nil }
        do {
            var acc = try rings(of: Editing2.bakedPaths(of: first), tolerance: tolerance)
            var rule = fillRule(of: first)
            if nodes.count == 1 {
                acc = clip(subject: acc, subjectRule: rule, clip: [], op: .union)
                rule = .evenOdd
            }
            for node in nodes.dropFirst() {
                let clipRings = try rings(of: Editing2.bakedPaths(of: node), tolerance: tolerance)
                acc = clip(
                    subject: acc, subjectRule: rule, clip: clipRings,
                    clipRule: fillRule(of: node), op: op)
                rule = .evenOdd
            }
            guard !acc.isEmpty else { return nil }
            var out = first
            out.kind = .path(acc.map(ringPath))
            out.transform = nil
            out.style.set("fill-rule", .keyword("evenodd"))
            return out
        } catch {
            return nil
        }
    }

    static func ringPath(_ ring: [Pt]) -> RefinedPath {
        RefinedPath(
            start: ring[0], segments: ring.dropFirst().map { .line(to: $0) }, closed: true)
    }

    // MARK: - Simplify

    /// Merge consecutive collinear line segments and drop degenerate
    /// (zero-length) segments in a `.path` node. An explicit closing line
    /// back to the start of a closed subpath becomes implicit. Primitives
    /// are returned untouched (a rect is already minimal).
    public static func simplifyNode(_ node: ShapeNode) -> ShapeNode {
        guard case .path(let paths) = node.kind else { return node }
        var out = node
        out.kind = .path(paths.map(simplifiedPath).filter { !$0.segments.isEmpty })
        return out
    }

    static func simplifiedPath(_ rp: RefinedPath) -> RefinedPath {
        var segs: [RefinedSegment] = []
        var starts: [Pt] = []
        var cur = rp.start
        for seg in rp.segments {
            if isDegenerate(seg, from: cur) { continue }
            if case .line(let to) = seg, case .line? = segs.last,
                let lastStart = starts.last, isStraightThrough(lastStart, cur, to)
            {
                segs[segs.count - 1] = .line(to: to)
            } else {
                segs.append(seg)
                starts.append(cur)
            }
            cur = seg.endPoint
        }
        if rp.closed, segs.count >= 3, case .line(let to)? = segs.last,
            samePoint(to, rp.start)
        {
            segs.removeLast()
            starts.removeLast()
        }
        return RefinedPath(start: rp.start, segments: segs, closed: rp.closed)
    }

    static func isDegenerate(_ seg: RefinedSegment, from cur: Pt) -> Bool {
        switch seg {
        case .line(let to):
            return samePoint(to, cur)
        case .cubic(let c1, let c2, let to):
            // A zero-length cubic with displaced controls still draws a loop;
            // only fully collapsed cubics are degenerate.
            return samePoint(to, cur) && samePoint(c1, cur) && samePoint(c2, cur)
        case .arc(_, let radius, _, _, _):
            return radius <= 1e-9
        }
    }

    static func samePoint(_ a: Pt, _ b: Pt) -> Bool {
        abs(a.x - b.x) <= 1e-9 && abs(a.y - b.y) <= 1e-9
    }

    /// b sits on the straight run a→c (within 1e-7 px) without reversing.
    static func isStraightThrough(_ a: Pt, _ b: Pt, _ c: Pt) -> Bool {
        let ux = b.x - a.x
        let uy = b.y - a.y
        let vx = c.x - b.x
        let vy = c.y - b.y
        guard ux * vx + uy * vy > 0 else { return false }
        return perpToChord(b, a, c) <= 1e-7
    }

    // MARK: - Join

    /// Concatenate open subpaths of two nodes whose endpoints meet within
    /// `tolerance` px (reversing chains as needed; a connector line bridges
    /// sub-tolerance gaps). A resulting chain whose own ends meet within
    /// tolerance is closed. Closed subpaths pass through untouched. The
    /// result adopts `a`'s style and attributes; geometry is baked.
    /// Returns nil when neither node carries any geometry.
    public static func joinPaths(_ a: ShapeNode, _ b: ShapeNode, tolerance: Double = 0.5)
        -> ShapeNode?
    {
        let paths = Editing2.bakedPaths(of: a) + Editing2.bakedPaths(of: b)
        guard !paths.isEmpty else { return nil }
        let closed = paths.filter { $0.closed }
        var chains = paths.filter { !$0.closed && !$0.segments.isEmpty }
        var merged = true
        while merged, chains.count > 1 {
            merged = false
            search: for i in 0..<chains.count {
                for j in (i + 1)..<chains.count {
                    if let joined = joinedChain(chains[i], chains[j], tolerance: tolerance) {
                        chains[i] = joined
                        chains.remove(at: j)
                        merged = true
                        break search
                    }
                }
            }
        }
        for i in chains.indices where chains[i].segments.count >= 2 {
            let end = chains[i].segments.last!.endPoint
            if distance(chains[i].start, end) <= tolerance { chains[i].closed = true }
        }
        var out = a
        out.kind = .path(closed + chains)
        out.transform = nil
        return out
    }

    /// Join two open chains at their closest endpoint pairing within
    /// tolerance, or nil when no pairing is close enough.
    static func joinedChain(_ x: RefinedPath, _ y: RefinedPath, tolerance: Double)
        -> RefinedPath?
    {
        let xs = x.start
        let xe = x.segments.last?.endPoint ?? x.start
        let ys = y.start
        let ye = y.segments.last?.endPoint ?? y.start
        // (gap, head chain, tail chain) — tail is appended after head.
        let options: [(Double, RefinedPath, RefinedPath)] = [
            (distance(xe, ys), x, y),
            (distance(xe, ye), x, Editing.reversed(y)),
            (distance(ye, xs), y, x),
            (distance(ys, xs), Editing.reversed(x), y),
        ]
        guard let best = options.min(by: { $0.0 < $1.0 }), best.0 <= tolerance else {
            return nil
        }
        let head = best.1
        let tail = best.2
        var segs = head.segments
        let headEnd = head.segments.last?.endPoint ?? head.start
        if distance(headEnd, tail.start) > 1e-9 { segs.append(.line(to: tail.start)) }
        segs.append(contentsOf: tail.segments)
        return RefinedPath(start: head.start, segments: segs, closed: false)
    }

    static func distance(_ a: Pt, _ b: Pt) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}
