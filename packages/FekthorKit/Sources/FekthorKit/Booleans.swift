import Foundation

// MARK: - Boolean operations: public vocabulary

/// A boolean operation combining two filled regions (subject ∘ clip).
public enum BoolOp: String, CaseIterable, Sendable {
    case union
    case subtract
    case intersect
    case exclude  // symmetric difference (xor)

    /// The region predicate: is a point inside the result given its
    /// membership in the subject and clip regions?
    func keeps(insideSubject a: Bool, insideClip b: Bool) -> Bool {
        switch self {
        case .union: return a || b
        case .subtract: return a && !b
        case .intersect: return a && b
        case .exclude: return a != b
        }
    }
}

/// SVG fill rule interpreting a ring set as a region. Inputs of either rule
/// are accepted; boolean results are always regular region boundaries, which
/// render identically under both rules (each result declares `evenodd`).
public enum FillRule: String, Sendable {
    case evenOdd
    case nonZero

    func isInside(winding: Int) -> Bool {
        switch self {
        case .evenOdd: return winding & 1 != 0
        case .nonZero: return winding != 0
        }
    }
}

/// Typed failures from path operations.
public enum PathOpsError: Error, Equatable, Sendable {
    /// Boolean operations require closed regions; subpath `index` is open.
    case openSubpath(index: Int)
}

// MARK: - Polygon overlay engine

/// Planar-overlay boolean core on polygon ring sets.
///
/// Algorithm (arrangement + winding propagation, a Martinez-Rueda-style
/// overlay without the sweep status structure — chosen for exact, epsilon-free
/// face classification):
/// 1. Snap every vertex to a 1e-7 grid (kills epsilon spray; equality is
///    exact integer comparison from here on).
/// 2. Split all edges (subject and clip together) at pairwise intersections,
///    collinear overlaps and vertex-on-edge touches, iterating until stable,
///    so no fragment interior meets any other fragment.
/// 3. Merge coincident fragments into canonical undirected fragments carrying
///    per-operand *signed* multiplicities (net winding delta across the
///    fragment). Opposite coincident edges cancel; fragments with zero net
///    effect on both operands drop out — this is what makes shared edges and
///    identical polygons exact, not approximate.
/// 4. Build the half-edge structure, extract face cycles (face-on-left via
///    the rotational-predecessor rule), and propagate per-operand winding
///    numbers across fragments: crossing a fragment changes each operand's
///    winding by that fragment's net multiplicity. Each connected component
///    is seeded at its topmost vertex, whose upward wedge is classified by a
///    weighted crossing count against the *other* components only (the point
///    provably lies on no other component after splitting).
/// 5. Classify every face by the operation predicate under each operand's
///    fill rule, and walk the kept/not-kept boundary into output rings with
///    the result region on the left (outer rings get positive shoelace area,
///    holes negative). Collinear vertices introduced by splitting are merged
///    back out.
///
/// Deterministic: array-ordered iteration everywhere, dictionaries are used
/// for lookup only, ties in angular sorting break on grid coordinates.
enum PolygonOverlay {
    /// Snap grid: 1e-7 px. Coordinates up to ~2000 px fit Int64 comfortably.
    static let gridScale = 1e7
    /// Weld radius for vertex-on-edge (T-junction) splitting, in px.
    static let weldDistance = 1.5e-7
    /// Weld radius in grid units, for bounding-box pruning.
    static let weldGrid: Int64 = 2

    struct GP: Hashable, Comparable {
        var x: Int64
        var y: Int64
        /// y-major so the minimum is the topmost (then leftmost) point.
        static func < (l: GP, r: GP) -> Bool {
            l.y != r.y ? l.y < r.y : l.x < r.x
        }
    }

    static func snap(_ p: Pt) -> GP {
        GP(x: Int64((p.x * gridScale).rounded()), y: Int64((p.y * gridScale).rounded()))
    }

    static func point(_ g: GP) -> Pt {
        Pt(Double(g.x) / gridScale, Double(g.y) / gridScale)
    }

    struct Edge {
        var a: GP
        var b: GP
        var subject: Bool
    }

    /// A canonical undirected fragment (a < b) with the signed number of
    /// input edges along a→b per operand (its winding delta when crossed).
    struct Fragment {
        var a: GP
        var b: GP
        var netSubject: Int
        var netClip: Int
    }

    // MARK: Entry

    /// Overlay two ring sets and return the boundary of `op` applied to the
    /// regions they describe under their fill rules. Output rings are
    /// even-odd-clean: outer boundaries have positive shoelace area, holes
    /// negative, and no point is enclosed by overlapping result rings.
    static func clip(
        subject: [[Pt]], subjectRule: FillRule, clip clipRings: [[Pt]], clipRule: FillRule,
        op: BoolOp
    ) -> [[Pt]] {
        var edges: [Edge] = []
        func add(_ rings: [[Pt]], subject: Bool) {
            for ring in rings where ring.count >= 3 {
                let g = ring.map(snap)
                for i in 0..<g.count {
                    let a = g[i]
                    let b = g[(i + 1) % g.count]
                    if a != b { edges.append(Edge(a: a, b: b, subject: subject)) }
                }
            }
        }
        add(subject, subject: true)
        add(clipRings, subject: false)
        guard !edges.isEmpty else { return [] }
        splitEdges(&edges)
        let frags = canonicalFragments(edges)
        guard !frags.isEmpty else { return [] }
        return extract(frags, subjectRule: subjectRule, clipRule: clipRule, op: op)
    }

    // MARK: Splitting

    /// Split all edges at mutual intersections and near-touches until no
    /// fragment interior contains another fragment's point. Snapping an
    /// intersection can create a fresh vertex-on-edge situation, hence the
    /// (bounded) fixpoint iteration.
    static func splitEdges(_ edges: inout [Edge]) {
        for _ in 0..<5 {
            var cuts = [[GP]](repeating: [], count: edges.count)
            let order = edges.indices.sorted {
                min(edges[$0].a.x, edges[$0].b.x) < min(edges[$1].a.x, edges[$1].b.x)
            }
            for oi in 0..<order.count {
                let i = order[oi]
                let ei = edges[i]
                let iMaxX = max(ei.a.x, ei.b.x)
                let iMinY = min(ei.a.y, ei.b.y)
                let iMaxY = max(ei.a.y, ei.b.y)
                for oj in (oi + 1)..<order.count {
                    let j = order[oj]
                    let ej = edges[j]
                    if min(ej.a.x, ej.b.x) > iMaxX + weldGrid { break }
                    if min(ej.a.y, ej.b.y) > iMaxY + weldGrid { continue }
                    if max(ej.a.y, ej.b.y) < iMinY - weldGrid { continue }
                    var ci: [GP] = []
                    var cj: [GP] = []
                    collectSplits(ei, ej, into: &ci, and: &cj)
                    if !ci.isEmpty { cuts[i].append(contentsOf: ci) }
                    if !cj.isEmpty { cuts[j].append(contentsOf: cj) }
                }
            }
            var changed = false
            var next: [Edge] = []
            next.reserveCapacity(edges.count)
            for (i, e) in edges.enumerated() {
                let pieces = subdivide(e, cuts: cuts[i])
                if pieces.count > 1 { changed = true }
                next.append(contentsOf: pieces)
            }
            edges = next
            if !changed { break }
        }
    }

    static func cross(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        ax * by - ay * bx
    }

    /// Intersection/touch points between two edges. Proper crossings add the
    /// snapped intersection to both; endpoint-on-edge welds (which also cover
    /// collinear overlaps, whose split points are always endpoints) add the
    /// existing endpoint so both edges stay exactly coincident there.
    static func collectSplits(_ e1: Edge, _ e2: Edge, into c1: inout [GP], and c2: inout [GP]) {
        let a = point(e1.a)
        let b = point(e1.b)
        let p = point(e2.a)
        let q = point(e2.b)
        let rx = b.x - a.x
        let ry = b.y - a.y
        let sx = q.x - p.x
        let sy = q.y - p.y
        let lenR = (rx * rx + ry * ry).squareRoot()
        let lenS = (sx * sx + sy * sy).squareRoot()
        let denom = cross(rx, ry, sx, sy)
        if abs(denom) > 1e-12 * lenR * lenS {
            let t = cross(p.x - a.x, p.y - a.y, sx, sy) / denom
            let u = cross(p.x - a.x, p.y - a.y, rx, ry) / denom
            if t >= -1e-9, t <= 1 + 1e-9, u >= -1e-9, u <= 1 + 1e-9 {
                let g = snap(Pt(a.x + t * rx, a.y + t * ry))
                c1.append(g)
                c2.append(g)
            }
        }
        weld(e2.a, ontoA: a, b: b, rx: rx, ry: ry, len: lenR, into: &c1)
        weld(e2.b, ontoA: a, b: b, rx: rx, ry: ry, len: lenR, into: &c1)
        weld(e1.a, ontoA: p, b: q, rx: sx, ry: sy, len: lenS, into: &c2)
        weld(e1.b, ontoA: p, b: q, rx: sx, ry: sy, len: lenS, into: &c2)
    }

    /// If grid vertex `g` lies on the interior of segment a→b within the weld
    /// radius, record it as a split point of that segment.
    static func weld(
        _ g: GP, ontoA a: Pt, b: Pt, rx: Double, ry: Double, len: Double, into cuts: inout [GP]
    ) {
        guard len > 0 else { return }
        let v = point(g)
        let t = ((v.x - a.x) * rx + (v.y - a.y) * ry) / (len * len)
        guard t > 0, t < 1 else { return }
        let px = a.x + t * rx - v.x
        let py = a.y + t * ry - v.y
        if (px * px + py * py).squareRoot() <= weldDistance { cuts.append(g) }
    }

    /// Split one edge at its collected cut points (sorted along the edge,
    /// endpoints and duplicates dropped).
    static func subdivide(_ e: Edge, cuts: [GP]) -> [Edge] {
        guard !cuts.isEmpty else { return [e] }
        let a = point(e.a)
        let b = point(e.b)
        let rx = b.x - a.x
        let ry = b.y - a.y
        let len2 = rx * rx + ry * ry
        guard len2 > 0 else { return [e] }
        var stops: [(t: Double, g: GP)] = []
        var seen = Set<GP>()
        for g in cuts where g != e.a && g != e.b && !seen.contains(g) {
            seen.insert(g)
            let p = point(g)
            let t = ((p.x - a.x) * rx + (p.y - a.y) * ry) / len2
            if t > 0, t < 1 { stops.append((t, g)) }
        }
        guard !stops.isEmpty else { return [e] }
        stops.sort { $0.t != $1.t ? $0.t < $1.t : $0.g < $1.g }
        var out: [Edge] = []
        var cur = e.a
        for (_, g) in stops where g != cur {
            out.append(Edge(a: cur, b: g, subject: e.subject))
            cur = g
        }
        if cur != e.b { out.append(Edge(a: cur, b: e.b, subject: e.subject)) }
        return out.isEmpty ? [e] : out
    }

    // MARK: Canonical fragments

    struct FragKey: Hashable {
        var a: GP
        var b: GP
    }

    static func canonicalFragments(_ edges: [Edge]) -> [Fragment] {
        var nets: [FragKey: (s: Int, c: Int)] = [:]
        for e in edges {
            let forward = e.a < e.b
            let key = forward ? FragKey(a: e.a, b: e.b) : FragKey(a: e.b, b: e.a)
            let d = forward ? 1 : -1
            var n = nets[key] ?? (0, 0)
            if e.subject { n.s += d } else { n.c += d }
            nets[key] = n
        }
        var frags: [Fragment] = []
        frags.reserveCapacity(nets.count)
        for (key, n) in nets where n.s != 0 || n.c != 0 {
            frags.append(Fragment(a: key.a, b: key.b, netSubject: n.s, netClip: n.c))
        }
        frags.sort { l, r in l.a != r.a ? l.a < r.a : l.b < r.b }
        return frags
    }

    // MARK: Face extraction & classification

    static func isLeft(_ a: Pt, _ b: Pt, _ p: Pt) -> Double {
        (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)
    }

    static func extract(
        _ frags: [Fragment], subjectRule: FillRule, clipRule: FillRule, op: BoolOp
    ) -> [[Pt]] {
        let n = frags.count
        // Vertices in first-seen (fragment-sorted) order.
        var vertexIndex: [GP: Int] = [:]
        var vertices: [GP] = []
        for f in frags {
            for g in [f.a, f.b] where vertexIndex[g] == nil {
                vertexIndex[g] = vertices.count
                vertices.append(g)
            }
        }

        // Half-edge h: 2*fi is a→b, 2*fi+1 is b→a; twin(h) = h ^ 1.
        func tail(_ h: Int) -> GP { h & 1 == 0 ? frags[h >> 1].a : frags[h >> 1].b }
        func head(_ h: Int) -> GP { h & 1 == 0 ? frags[h >> 1].b : frags[h >> 1].a }
        var angles = [Double](repeating: 0, count: 2 * n)
        for h in 0..<(2 * n) {
            let t = tail(h)
            let w = head(h)
            angles[h] = atan2(Double(w.y - t.y), Double(w.x - t.x))
        }

        // Outgoing half-edges per vertex, sorted ccw (ascending angle).
        var outgoing = [[Int]](repeating: [], count: vertices.count)
        for h in 0..<(2 * n) { outgoing[vertexIndex[tail(h)]!].append(h) }
        var posInOutgoing = [Int](repeating: 0, count: 2 * n)
        for vi in outgoing.indices {
            outgoing[vi].sort { l, r in
                angles[l] != angles[r] ? angles[l] < angles[r] : head(l) < head(r)
            }
            for (k, h) in outgoing[vi].enumerated() { posInOutgoing[h] = k }
        }

        // Face-on-left traversal: the successor of h is the rotational
        // predecessor (next clockwise) of twin(h) around head(h).
        func next(_ h: Int) -> Int {
            let list = outgoing[vertexIndex[head(h)]!]
            let k = posInOutgoing[h ^ 1]
            return list[(k - 1 + list.count) % list.count]
        }

        // Face cycles.
        var cycleOf = [Int](repeating: -1, count: 2 * n)
        var cycleCount = 0
        for h0 in 0..<(2 * n) where cycleOf[h0] == -1 {
            var h = h0
            var guardCount = 0
            repeat {
                cycleOf[h] = cycleCount
                h = next(h)
                guardCount += 1
            } while h != h0 && guardCount <= 2 * n
            cycleCount += 1
        }

        // Connected components over vertices (fragments as edges).
        var parent = Array(0..<vertices.count)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var c = x
            while parent[c] != r {
                let p = parent[c]
                parent[c] = r
                c = p
            }
            return r
        }
        for f in frags {
            let ra = find(vertexIndex[f.a]!)
            let rb = find(vertexIndex[f.b]!)
            if ra != rb { parent[ra] = rb }
        }
        var fragComponent = [Int](repeating: 0, count: n)
        for fi in 0..<n { fragComponent[fi] = find(vertexIndex[frags[fi].a]!) }

        // Per-operand winding of a point against fragments of OTHER
        // components (weighted crossing count; standard half-open rules).
        func seedWinding(at p: Pt, excluding comp: Int) -> (s: Int, c: Int) {
            var ws = 0
            var wc = 0
            for fi in 0..<n where fragComponent[fi] != comp {
                let f = frags[fi]
                let a = point(f.a)
                let b = point(f.b)
                if a.y <= p.y {
                    if b.y > p.y, isLeft(a, b, p) > 0 {
                        ws += f.netSubject
                        wc += f.netClip
                    }
                } else if b.y <= p.y, isLeft(a, b, p) < 0 {
                    ws -= f.netSubject
                    wc -= f.netClip
                }
            }
            return (ws, wc)
        }

        // Winding labels per cycle, propagated across fragments: the face on
        // the right of a→b has winding(left) − net(a→b).
        var windS = [Int?](repeating: nil, count: cycleCount)
        var windC = [Int?](repeating: nil, count: cycleCount)
        var adjacency = [[(other: Int, ds: Int, dc: Int)]](repeating: [], count: cycleCount)
        for fi in 0..<n {
            let l = cycleOf[2 * fi]
            let r = cycleOf[2 * fi + 1]
            let f = frags[fi]
            adjacency[l].append((r, -f.netSubject, -f.netClip))
            adjacency[r].append((l, f.netSubject, f.netClip))
        }

        // Seed each component at its topmost vertex: the wedge containing the
        // straight-up direction there belongs to the left face of the
        // max-angle outgoing edge (all outgoing angles lie in [0, π]).
        var seededComponents = Set<Int>()
        for vi in vertices.indices {
            let comp = find(vi)
            guard !seededComponents.contains(comp) else { continue }
            // Topmost vertex of the component = first in GP-sorted order.
            var top = vi
            for vj in vertices.indices where find(vj) == comp {
                if vertices[vj] < vertices[top] { top = vj }
            }
            seededComponents.insert(comp)
            guard let ambient = outgoing[top].last else { continue }
            let ambientCycle = cycleOf[ambient]
            let seed = seedWinding(at: point(vertices[top]), excluding: comp)
            guard windS[ambientCycle] == nil else { continue }
            windS[ambientCycle] = seed.s
            windC[ambientCycle] = seed.c
            var queue = [ambientCycle]
            var qi = 0
            while qi < queue.count {
                let c = queue[qi]
                qi += 1
                for (other, ds, dc) in adjacency[c] where windS[other] == nil {
                    windS[other] = windS[c]! + ds
                    windC[other] = windC[c]! + dc
                    queue.append(other)
                }
            }
        }

        var kept = [Bool](repeating: false, count: cycleCount)
        for c in 0..<cycleCount {
            let a = subjectRule.isInside(winding: windS[c] ?? 0)
            let b = clipRule.isInside(winding: windC[c] ?? 0)
            kept[c] = op.keeps(insideSubject: a, insideClip: b)
        }

        // Result boundary: half-edges whose left face is kept and whose
        // twin's is not, chained through kept faces around each vertex.
        func isBoundary(_ h: Int) -> Bool { kept[cycleOf[h]] && !kept[cycleOf[h ^ 1]] }
        var used = [Bool](repeating: false, count: 2 * n)
        var rings: [[Pt]] = []
        for h0 in 0..<(2 * n) where isBoundary(h0) && !used[h0] {
            var ring: [GP] = []
            var h = h0
            var ok = true
            repeat {
                used[h] = true
                ring.append(tail(h))
                var g = next(h)
                var spins = 0
                while !isBoundary(g) {
                    g = next(g ^ 1)
                    spins += 1
                    if spins > 2 * n {
                        ok = false
                        break
                    }
                }
                h = g
                if ring.count > 2 * n + 4 { ok = false }
            } while h != h0 && ok
            if ok, let cleaned = cleanRing(ring) { rings.append(cleaned) }
        }
        return rings
    }

    /// Drop consecutive duplicates and straight-through collinear vertices
    /// reintroduced by edge splitting; reject degenerate rings.
    static func cleanRing(_ ring: [GP]) -> [Pt]? {
        var pts = ring
        var changed = true
        while changed, pts.count >= 3 {
            changed = false
            var out: [GP] = []
            out.reserveCapacity(pts.count)
            let m = pts.count
            for i in 0..<m {
                let prev = pts[(i + m - 1) % m]
                let cur = pts[i]
                let nxt = pts[(i + 1) % m]
                if cur == prev {
                    changed = true
                    continue
                }
                let ux = Double(cur.x - prev.x)
                let uy = Double(cur.y - prev.y)
                let vx = Double(nxt.x - cur.x)
                let vy = Double(nxt.y - cur.y)
                let crossUV = ux * vy - uy * vx
                let dot = ux * vx + uy * vy
                let chord = ((ux + vx) * (ux + vx) + (uy + vy) * (uy + vy)).squareRoot()
                // Straight through: within 2 grid units of the chord.
                if dot > 0, chord > 0, abs(crossUV) / chord <= 2 {
                    changed = true
                    continue
                }
                out.append(cur)
            }
            pts = out
        }
        guard pts.count >= 3 else { return nil }
        let result = pts.map(point)
        guard abs(Geometry.signedArea(result)) > 1e-10 else { return nil }
        return result
    }
}
