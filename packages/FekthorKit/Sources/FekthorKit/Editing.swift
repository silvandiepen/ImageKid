import Foundation

/// Node editing V1 (engine side): enumerate a document element's anchor points
/// and apply anchor moves. The app draws the anchors and feeds drags back here,
/// so the geometry rules live in one testable place.
///
/// Rules:
/// - A refined path's anchors are its start plus each segment end. Moving an
///   anchor translates the adjacent cubic control points with it, so the curve
///   keeps its shape locally instead of pinching.
/// - Arcs are parametric (centre/radius/angles) and cannot follow a free-moved
///   endpoint; a path containing arcs is degraded to cubics ONCE on its first
///   edit (visually identical within a fraction of a pixel).
/// - Primitives (circle/ellipse/rect) expose one anchor — their centre — and
///   move rigidly. Legacy rings expose every vertex.
public enum Editing {
    public struct Anchor {
        /// Which ring/path inside the element (fills can have holes).
        public var path: Int
        /// Anchor index within that path (0 = start).
        public var index: Int
        public var position: Pt
    }

    // MARK: - Anchor enumeration

    public static func anchors(of element: Element) -> [Anchor] {
        switch element {
        case .stroke(let s):
            if let rp = s.refined { return pathAnchors(rp, path: 0) }
            return s.points.enumerated().map { Anchor(path: 0, index: $0.0, position: $0.1) }
        case .fill(let f):
            switch f.geometry {
            case .refined(let paths):
                var out: [Anchor] = []
                for (pi, rp) in paths.enumerated() {
                    out.append(contentsOf: pathAnchors(rp, path: pi))
                }
                return out
            case .rings(let rings):
                var out: [Anchor] = []
                for (ri, ring) in rings.enumerated() {
                    for (i, p) in ring.enumerated() {
                        out.append(Anchor(path: ri, index: i, position: p))
                    }
                }
                return out
            case .circle(let c, _):
                return [Anchor(path: 0, index: 0, position: c)]
            case .ellipse(let c, _, _, _):
                return [Anchor(path: 0, index: 0, position: c)]
            case .rect(let c, _, _, _, _):
                return [Anchor(path: 0, index: 0, position: c)]
            }
        }
    }

    static func pathAnchors(_ rp: RefinedPath, path: Int) -> [Anchor] {
        var out = [Anchor(path: path, index: 0, position: rp.start)]
        for (i, seg) in rp.segments.enumerated() {
            out.append(Anchor(path: path, index: i + 1, position: seg.endPoint))
        }
        // A closed path's final segment usually lands back on the start; that
        // seam is ONE anchor, not two (moving the duplicate would tear the
        // loop — the start move already drags the closing segment's end).
        if rp.closed, out.count > 1 {
            let last = out[out.count - 1].position
            let dx = last.x - rp.start.x
            let dy = last.y - rp.start.y
            if dx * dx + dy * dy < 0.25 { out.removeLast() }
        }
        return out
    }

    // MARK: - Anchor moves

    /// Returns the element with the given anchor moved to `to`.
    public static func move(
        _ element: Element, path: Int, anchor: Int, to: Pt
    ) -> Element {
        switch element {
        case .stroke(var s):
            if let rp = s.refined {
                s.refined = movedPath(rp, anchor: anchor, to: to)
                // Keep the fallback polyline loosely in sync for scoring.
                s.points = PathRefine.flatten(s.refined!)
            } else if anchor < s.points.count {
                s.points[anchor] = to
            }
            return .stroke(s)
        case .fill(var f):
            switch f.geometry {
            case .refined(var paths):
                if path < paths.count {
                    paths[path] = movedPath(paths[path], anchor: anchor, to: to)
                    f.geometry = .refined(paths)
                }
            case .rings(var rings):
                if path < rings.count, anchor < rings[path].count {
                    rings[path][anchor] = to
                    f.geometry = .rings(rings)
                }
            case .circle(let c, let r):
                f.geometry = .circle(center: shifted(c, c, to), radius: r)
            case .ellipse(let c, let rx, let ry, let rot):
                f.geometry = .ellipse(center: shifted(c, c, to), rx: rx, ry: ry, rotation: rot)
            case .rect(let c, let w, let h, let rot, let cr):
                f.geometry = .rect(
                    center: shifted(c, c, to), w: w, h: h, rotation: rot, cornerRadius: cr)
            }
            return .fill(f)
        }
    }

    @inline(__always) static func shifted(_ p: Pt, _ from: Pt, _ to: Pt) -> Pt {
        Pt(p.x + (to.x - from.x), p.y + (to.y - from.y))
    }

    static func movedPath(_ rp: RefinedPath, anchor: Int, to: Pt) -> RefinedPath {
        var path = cubicized(rp)
        let n = path.segments.count
        if anchor == 0 {
            let d = (to.x - path.start.x, to.y - path.start.y)
            // Outgoing control follows the start.
            if n > 0, case .cubic(let c1, let c2, let end) = path.segments[0] {
                path.segments[0] = .cubic(
                    c1: Pt(c1.x + d.0, c1.y + d.1), c2: c2, to: end)
            }
            // On a closed path the last segment ends at the start — move that
            // end (and its incoming control) too, or the loop tears open.
            if path.closed, n > 0 {
                path.segments[n - 1] = movedEnd(path.segments[n - 1], to: to)
            }
            path.start = to
            return path
        }
        let i = anchor - 1
        guard i >= 0, i < n else { return path }
        let old = path.segments[i].endPoint
        let d = (to.x - old.x, to.y - old.y)
        path.segments[i] = movedEnd(path.segments[i], to: to)
        // The outgoing control belongs to the joint we just moved; keep it
        // attached so the curve translates locally instead of pinching.
        if i + 1 < n, case .cubic(let c1, let c2, let end) = path.segments[i + 1] {
            path.segments[i + 1] = .cubic(
                c1: Pt(c1.x + d.0, c1.y + d.1), c2: c2, to: end)
        }
        return path
    }

    static func movedEnd(_ seg: RefinedSegment, to: Pt) -> RefinedSegment {
        switch seg {
        case .line: return .line(to: to)
        case .cubic(let c1, let c2, let old):
            // Incoming control follows the endpoint.
            return .cubic(
                c1: c1, c2: Pt(c2.x + (to.x - old.x), c2.y + (to.y - old.y)), to: to)
        case .arc:
            // cubicized() removes arcs before any move; unreachable, but keep
            // the compiler total.
            return .line(to: to)
        }
    }

    // MARK: - Control handles

    public enum HandleKind: Sendable { case c1, c2 }

    /// A cubic control point adjacent to an anchor: the incoming segment's c2
    /// and/or the outgoing segment's c1.
    public struct Handle {
        public var path: Int
        /// Segment index inside the (cubicized) path.
        public var segment: Int
        public var kind: HandleKind
        public var position: Pt
        /// The anchor this handle belongs to (for drawing the lever line).
        public var anchor: Pt
    }

    /// Control handles adjacent to one anchor. Only cubic segments have
    /// handles; call after the path has been cubicized (any edit does that).
    public static func handles(
        of element: Element, path: Int, anchor: Int
    ) -> [Handle] {
        guard let rp = refinedPath(of: element, at: path) else { return [] }
        let cubed = cubicized(rp)
        let n = cubed.segments.count
        var out: [Handle] = []
        let anchorPos: Pt =
            anchor == 0
            ? cubed.start
            : (anchor - 1 < n ? cubed.segments[anchor - 1].endPoint : cubed.start)
        // Incoming segment: for anchor 0 on a closed path that's the last one.
        let incoming = anchor == 0 ? (cubed.closed ? n - 1 : -1) : anchor - 1
        if incoming >= 0, incoming < n, case .cubic(_, let c2, _) = cubed.segments[incoming] {
            out.append(
                Handle(path: path, segment: incoming, kind: .c2, position: c2, anchor: anchorPos))
        }
        let outgoing = anchor == 0 ? 0 : anchor
        if outgoing < n, case .cubic(let c1, _, _) = cubed.segments[outgoing] {
            out.append(
                Handle(path: path, segment: outgoing, kind: .c1, position: c1, anchor: anchorPos))
        }
        return out
    }

    /// Move one cubic control point. The element's path is cubicized first, so
    /// segment indices line up with what `handles(of:path:anchor:)` reported.
    /// With `mirror` (smooth point), the opposite handle across the shared
    /// anchor rotates to stay collinear — its own length is preserved — so the
    /// curve keeps a straight tangent through the anchor.
    public static func moveHandle(
        _ element: Element, path: Int, segment: Int, kind: HandleKind, to: Pt,
        mirror: Bool = false
    ) -> Element {
        guard let rp = refinedPath(of: element, at: path) else { return element }
        var cubed = cubicized(rp)
        let n = cubed.segments.count
        guard segment < n, case .cubic(let c1, let c2, let end) = cubed.segments[segment]
        else { return element }
        cubed.segments[segment] =
            kind == .c1 ? .cubic(c1: to, c2: c2, to: end) : .cubic(c1: c1, c2: to, to: end)

        if mirror {
            // The dragged handle's anchor and the opposite segment around it.
            let anchor: Pt
            var oppIndex: Int? = nil
            var oppKind: HandleKind = .c2
            if kind == .c1 {
                anchor = segment == 0 ? cubed.start : cubed.segments[segment - 1].endPoint
                if segment > 0 {
                    oppIndex = segment - 1
                } else if cubed.closed {
                    oppIndex = n - 1
                }
                oppKind = .c2
            } else {
                anchor = end
                if segment + 1 < n {
                    oppIndex = segment + 1
                } else if cubed.closed {
                    oppIndex = 0
                }
                oppKind = .c1
            }
            if let oi = oppIndex, oi < n, case .cubic(let oc1, let oc2, let oend) = cubed.segments[oi] {
                let old = oppKind == .c1 ? oc1 : oc2
                let len = ((old.x - anchor.x) * (old.x - anchor.x)
                    + (old.y - anchor.y) * (old.y - anchor.y)).squareRoot()
                let dx = anchor.x - to.x
                let dy = anchor.y - to.y
                let m = (dx * dx + dy * dy).squareRoot()
                if m > 1e-9, len > 1e-9 {
                    let mirrored = Pt(anchor.x + dx / m * len, anchor.y + dy / m * len)
                    cubed.segments[oi] =
                        oppKind == .c1
                        ? .cubic(c1: mirrored, c2: oc2, to: oend)
                        : .cubic(c1: oc1, c2: mirrored, to: oend)
                }
            }
        }
        return replacingPath(element, at: path, with: cubed)
    }

    static func refinedPath(of element: Element, at path: Int) -> RefinedPath? {
        switch element {
        case .stroke(let s): return path == 0 ? s.refined : nil
        case .fill(let f):
            if case .refined(let paths) = f.geometry, path < paths.count { return paths[path] }
            return nil
        }
    }

    static func replacingPath(_ element: Element, at path: Int, with rp: RefinedPath) -> Element {
        switch element {
        case .stroke(var s):
            if path == 0 {
                s.refined = rp
                s.points = PathRefine.flatten(rp)
            }
            return .stroke(s)
        case .fill(var f):
            if case .refined(var paths) = f.geometry, path < paths.count {
                paths[path] = rp
                f.geometry = .refined(paths)
            }
            return .fill(f)
        }
    }

    // MARK: - Arc degrade

    /// Replace every arc with cubic Bézier spans (≤90° each, k = 4/3·tan(θ/4)):
    /// the standard approximation, within ~0.03% of the true circle.
    public static func cubicized(_ rp: RefinedPath) -> RefinedPath {
        guard rp.segments.contains(where: { if case .arc = $0 { return true } else { return false } })
        else { return rp }
        var segments: [RefinedSegment] = []
        var current = rp.start
        for seg in rp.segments {
            switch seg {
            case .line, .cubic:
                segments.append(seg)
                current = seg.endPoint
            case .arc(let c, let r, let sa, let ea, let cw):
                var sweep = cw ? ea - sa : sa - ea
                while sweep < 0 { sweep += 2 * .pi }
                while sweep >= 2 * .pi { sweep -= 2 * .pi }
                let dir: Double = cw ? 1 : -1
                let chunks = max(1, Int(ceil(sweep / (.pi / 2))))
                let step = sweep / Double(chunks)
                var a0 = sa
                for _ in 0..<chunks {
                    let a1 = a0 + dir * step
                    let k = 4.0 / 3.0 * tan(step / 4)
                    let p0 = Pt(c.x + r * cos(a0), c.y + r * sin(a0))
                    let p3 = Pt(c.x + r * cos(a1), c.y + r * sin(a1))
                    // Tangents rotate with the traversal direction.
                    let t0 = Pt(-sin(a0) * dir, cos(a0) * dir)
                    let t3 = Pt(-sin(a1) * dir, cos(a1) * dir)
                    let c1 = Pt(p0.x + k * r * t0.x, p0.y + k * r * t0.y)
                    let c2 = Pt(p3.x - k * r * t3.x, p3.y - k * r * t3.y)
                    segments.append(.cubic(c1: c1, c2: c2, to: p3))
                    a0 = a1
                }
                current = segments.last!.endPoint
            }
        }
        _ = current
        return RefinedPath(start: rp.start, segments: segments, closed: rp.closed)
    }
}

// MARK: - Break & merge (editor tools)

extension Editing {
    /// A reference to one anchor of one element in a document.
    public struct AnchorRef: Hashable, Sendable {
        public var element: Int
        public var path: Int
        public var anchor: Int
        public init(element: Int, path: Int, anchor: Int) {
            self.element = element
            self.path = path
            self.anchor = anchor
        }
    }

    /// Reverse a refined path (cubicized first — arcs cannot be flipped in
    /// place). Segment controls swap and the walk order inverts.
    public static func reversed(_ rp: RefinedPath) -> RefinedPath {
        let path = cubicized(rp)
        var points: [Pt] = [path.start]
        for seg in path.segments { points.append(seg.endPoint) }
        var segments: [RefinedSegment] = []
        for i in stride(from: path.segments.count - 1, through: 0, by: -1) {
            let from = points[i]
            switch path.segments[i] {
            case .line:
                segments.append(.line(to: from))
            case .cubic(let c1, let c2, _):
                segments.append(.cubic(c1: c2, c2: c1, to: from))
            case .arc:
                segments.append(.line(to: from))  // unreachable post-cubicize
            }
        }
        return RefinedPath(start: points.last ?? path.start, segments: segments, closed: path.closed)
    }

    /// Break a stroke at an interior anchor into two strokes, or cut a closed
    /// stroke open at any anchor. Returns nil when the anchor cannot break the
    /// element (fills, primitives, terminal anchors of open strokes).
    public static func breakAt(_ element: Element, path: Int, anchor: Int) -> [Element]? {
        guard case .stroke(let s) = element, path == 0, let rp0 = s.refined else { return nil }
        let rp = cubicized(rp0)
        let n = rp.segments.count
        guard n >= 2 else { return nil }

        func stroke(_ suffix: String, _ p: RefinedPath, closed: Bool) -> Element {
            var out = s
            out.id = s.id + suffix
            out.closed = closed
            out.refined = p
            out.points = PathRefine.flatten(p)
            return .stroke(out)
        }

        if rp.closed {
            // Cut the loop open at the anchor: same geometry, new start.
            var pts: [Pt] = [rp.start]
            for seg in rp.segments { pts.append(seg.endPoint) }
            let cut = min(max(anchor, 0), n - 1)
            let rotated = Array(rp.segments[cut...]) + Array(rp.segments[..<cut])
            let start = cut == 0 ? rp.start : rp.segments[cut - 1].endPoint
            let open = RefinedPath(start: start, segments: rotated, closed: false)
            return [stroke("-cut", open, closed: false)]
        }

        guard anchor >= 1, anchor <= n - 1 else { return nil }
        let firstPath = RefinedPath(
            start: rp.start, segments: Array(rp.segments[..<anchor]), closed: false)
        let secondStart = rp.segments[anchor - 1].endPoint
        let secondPath = RefinedPath(
            start: secondStart, segments: Array(rp.segments[anchor...]), closed: false)
        return [stroke("-a", firstPath, closed: false), stroke("-b", secondPath, closed: false)]
    }

    /// True when the ref points at a terminal anchor of an OPEN stroke.
    static func terminalInfo(_ doc: VectorDocument, _ ref: AnchorRef)
        -> (isStart: Bool, stroke: StrokePath)?
    {
        guard ref.element < doc.elements.count,
            case .stroke(let s) = doc.elements[ref.element], !s.closed, let rp = s.refined
        else { return nil }
        let count = pathAnchors(rp, path: 0).count
        if ref.anchor == 0 { return (true, s) }
        if ref.anchor == count - 1 { return (false, s) }
        return nil
    }

    /// Merge the referenced anchors: every anchor moves to the shared centroid.
    /// When exactly two refs are terminal anchors of open strokes, the strokes
    /// are additionally JOINED into one (or the stroke closes into a loop when
    /// both ends belong to the same stroke).
    public static func merge(_ doc: VectorDocument, refs: [AnchorRef]) -> VectorDocument {
        guard refs.count >= 2 else { return doc }
        var document = doc

        // Centroid of the current anchor positions.
        var cx = 0.0
        var cy = 0.0
        var found = 0
        for ref in refs where ref.element < document.elements.count {
            let list = anchors(of: document.elements[ref.element])
            if let a = list.first(where: { $0.path == ref.path && $0.index == ref.anchor }) {
                cx += a.position.x
                cy += a.position.y
                found += 1
            }
        }
        guard found >= 2 else { return doc }
        let target = Pt(cx / Double(found), cy / Double(found))
        for ref in refs where ref.element < document.elements.count {
            document.elements[ref.element] = move(
                document.elements[ref.element], path: ref.path, anchor: ref.anchor, to: target)
        }

        // Join two open stroke ends into one stroke.
        guard refs.count == 2,
            let a = terminalInfo(document, refs[0]),
            let b = terminalInfo(document, refs[1])
        else { return document }

        if refs[0].element == refs[1].element {
            // Both ends of the same stroke: close the loop.
            guard refs[0].anchor != refs[1].anchor, case .stroke(var s) = document.elements[refs[0].element],
                let rp = s.refined
            else { return document }
            var closedPath = cubicized(rp)
            closedPath.closed = true
            s.closed = true
            s.refined = closedPath
            s.points = PathRefine.flatten(closedPath)
            document.elements[refs[0].element] = .stroke(s)
            return document
        }

        // Different strokes: orient A to END at the weld and B to START there,
        // then concatenate. B's element is removed.
        guard let rpA = a.stroke.refined, let rpB = b.stroke.refined else { return document }
        let partA = a.isStart ? reversed(rpA) : cubicized(rpA)
        let partB = b.isStart ? cubicized(rpB) : reversed(rpB)
        let joinedPath = RefinedPath(
            start: partA.start, segments: partA.segments + partB.segments, closed: false)
        var joined = a.stroke
        joined.id = a.stroke.id + "+" + b.stroke.id
        joined.refined = joinedPath
        joined.points = PathRefine.flatten(joinedPath)
        document.elements[refs[0].element] = .stroke(joined)
        document.elements.remove(at: refs[1].element)
        return document
    }
}

// MARK: - Remove point

extension Editing {
    /// Merge two consecutive segments into one, keeping the outer tangents:
    /// the incoming control of the first and the outgoing control of the
    /// second survive; the shared anchor disappears. Two lines stay a line.
    static func mergedSegment(from: Pt, _ a: RefinedSegment, _ b: RefinedSegment)
        -> RefinedSegment
    {
        if case .line = a, case .line(let to) = b { return .line(to: to) }
        let mid = a.endPoint
        let end = b.endPoint
        let c1: Pt
        switch a {
        case .cubic(let ac1, _, _): c1 = ac1
        default:
            c1 = Pt(from.x + (mid.x - from.x) / 3, from.y + (mid.y - from.y) / 3)
        }
        let c2: Pt
        switch b {
        case .cubic(_, let bc2, _): c2 = bc2
        default:
            c2 = Pt(end.x - (end.x - mid.x) / 3, end.y - (end.y - mid.y) / 3)
        }
        return .cubic(c1: c1, c2: c2, to: end)
    }

    static func removingAnchor(_ rp0: RefinedPath, anchor: Int) -> RefinedPath? {
        let rp = cubicized(rp0)
        let n = rp.segments.count
        if !rp.closed {
            guard n >= 2 else { return nil }
            if anchor <= 0 {
                return RefinedPath(
                    start: rp.segments[0].endPoint,
                    segments: Array(rp.segments.dropFirst()), closed: false)
            }
            if anchor >= n {
                return RefinedPath(
                    start: rp.start, segments: Array(rp.segments.dropLast()), closed: false)
            }
            var segs = rp.segments
            let from = anchor >= 2 ? segs[anchor - 2].endPoint : rp.start
            let merged = mergedSegment(from: from, segs[anchor - 1], segs[anchor])
            segs.replaceSubrange((anchor - 1)...anchor, with: [merged])
            return RefinedPath(start: rp.start, segments: segs, closed: false)
        }
        // Closed: every anchor is interior; keep at least a triangle.
        guard n >= 4 else { return nil }
        let k = ((anchor % n) + n) % n
        if k == 0 {
            // Remove the seam anchor: the last and first segments merge, and
            // the path re-anchors at the old first segment's end.
            let from = rp.segments[n - 2].endPoint
            let merged = mergedSegment(from: from, rp.segments[n - 1], rp.segments[0])
            var segs = Array(rp.segments[1..<(n - 1)])
            segs.append(merged)
            return RefinedPath(start: rp.segments[0].endPoint, segments: segs, closed: true)
        }
        var segs = rp.segments
        let from = k >= 2 ? segs[k - 2].endPoint : rp.start
        let merged = mergedSegment(from: from, segs[k - 1], segs[k])
        segs.replaceSubrange((k - 1)...k, with: [merged])
        return RefinedPath(start: rp.start, segments: segs, closed: true)
    }

    /// Remove one anchor. End anchors shorten an open stroke; interior anchors
    /// simplify the path (adjacent segments merge, tangents preserved).
    /// Returns nil when removal is impossible (primitives, paths already at
    /// their minimum size).
    public static func removeAnchor(_ element: Element, path: Int, anchor: Int) -> Element? {
        switch element {
        case .stroke(var s):
            guard path == 0, let rp = s.refined,
                let removed = removingAnchor(rp, anchor: anchor)
            else { return nil }
            s.refined = removed
            s.points = PathRefine.flatten(removed)
            return .stroke(s)
        case .fill(var f):
            switch f.geometry {
            case .refined(var paths):
                guard path < paths.count,
                    let removed = removingAnchor(paths[path], anchor: anchor)
                else { return nil }
                paths[path] = removed
                f.geometry = .refined(paths)
                return .fill(f)
            case .rings(var rings):
                guard path < rings.count, rings[path].count > 3,
                    anchor < rings[path].count
                else { return nil }
                rings[path].remove(at: anchor)
                f.geometry = .rings(rings)
                return .fill(f)
            case .circle, .ellipse, .rect:
                return nil
            }
        }
    }
}

// MARK: - Insert point

extension Editing {
    @inline(__always) static func lerp(_ a: Pt, _ b: Pt, _ t: Double) -> Pt {
        Pt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }

    /// Start point of segment `i` (the previous segment's end, or the path start).
    @inline(__always) static func segmentStart(_ rp: RefinedPath, _ i: Int) -> Pt {
        i == 0 ? rp.start : rp.segments[i - 1].endPoint
    }

    /// Point on segment `i` at parameter `t` in [0, 1].
    static func segmentPoint(_ rp: RefinedPath, _ i: Int, _ t: Double) -> Pt {
        let from = segmentStart(rp, i)
        switch rp.segments[i] {
        case .line(let to):
            return lerp(from, to, t)
        case .cubic(let c1, let c2, let to):
            let u = 1 - t
            let x =
                u * u * u * from.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x
                + t * t * t * to.x
            let y =
                u * u * u * from.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y
                + t * t * t * to.y
            return Pt(x, y)
        case .arc(let c, let r, let sa, let ea, let cw):
            var sweep = cw ? ea - sa : sa - ea
            while sweep < 0 { sweep += 2 * .pi }
            while sweep >= 2 * .pi { sweep -= 2 * .pi }
            let a = sa + (cw ? 1 : -1) * sweep * t
            return Pt(c.x + r * cos(a), c.y + r * sin(a))
        }
    }

    /// Split segment `segment` at parameter `t` (clamped to 0…1), adding one
    /// anchor WITHOUT changing the drawn geometry: cubics split exactly by
    /// de Casteljau, lines split linearly, and arcs are cubicized first (the
    /// same degrade rule every anchor-level edit applies).
    public static func insertingAnchor(_ path: RefinedPath, segment: Int, t: Double)
        -> RefinedPath
    {
        var rp = cubicized(path)
        let n = rp.segments.count
        guard n > 0 else { return rp }
        let i = min(max(segment, 0), n - 1)
        let u = min(max(t, 0), 1)
        let from = segmentStart(rp, i)
        let replacement: [RefinedSegment]
        switch rp.segments[i] {
        case .line(let to):
            replacement = [.line(to: lerp(from, to, u)), .line(to: to)]
        case .cubic(let c1, let c2, let to):
            // de Casteljau: both halves reproduce the original curve exactly.
            let q0 = lerp(from, c1, u)
            let q1 = lerp(c1, c2, u)
            let q2 = lerp(c2, to, u)
            let r0 = lerp(q0, q1, u)
            let r1 = lerp(q1, q2, u)
            let s = lerp(r0, r1, u)
            replacement = [.cubic(c1: q0, c2: r0, to: s), .cubic(c1: r1, c2: q2, to: to)]
        case .arc:
            replacement = [rp.segments[i]]  // unreachable post-cubicize
        }
        rp.segments.replaceSubrange(i...i, with: replacement)
        return rp
    }

    /// The closest point on a path's outline to `p` — the hit test behind
    /// ⌘-click "add point". Lines project exactly; cubics use coarse samples
    /// with two local refinement rounds (plenty for a click). The reported
    /// segment/t index into the CUBICIZED path, ready for `insertingAnchor`.
    public static func closestPoint(on path: RefinedPath, to p: Pt)
        -> (segment: Int, t: Double, point: Pt, distance: Double)
    {
        let rp = cubicized(path)
        func dist2(_ a: Pt) -> Double {
            (a.x - p.x) * (a.x - p.x) + (a.y - p.y) * (a.y - p.y)
        }
        guard !rp.segments.isEmpty else {
            return (0, 0, rp.start, dist2(rp.start).squareRoot())
        }
        var best = (segment: 0, t: 0.0, point: rp.start, d2: dist2(rp.start))
        for i in rp.segments.indices {
            switch rp.segments[i] {
            case .line(let to):
                let from = segmentStart(rp, i)
                let dx = to.x - from.x
                let dy = to.y - from.y
                let len2 = dx * dx + dy * dy
                let t =
                    len2 < 1e-12
                    ? 0 : min(1, max(0, ((p.x - from.x) * dx + (p.y - from.y) * dy) / len2))
                let q = lerp(from, to, t)
                let d = dist2(q)
                if d < best.d2 { best = (i, t, q, d) }
            default:
                // Coarse samples, then refine the window around the winner.
                var lo = 0.0
                var hi = 1.0
                var steps = 16
                for _ in 0..<3 {
                    var winT = lo
                    var winD = Double.greatestFiniteMagnitude
                    for k in 0...steps {
                        let t = lo + (hi - lo) * Double(k) / Double(steps)
                        let d = dist2(segmentPoint(rp, i, t))
                        if d < winD {
                            winD = d
                            winT = t
                        }
                    }
                    if winD < best.d2 {
                        best = (i, winT, segmentPoint(rp, i, winT), winD)
                    }
                    let w = (hi - lo) / Double(steps)
                    lo = max(0, winT - w)
                    hi = min(1, winT + w)
                    steps = 8
                }
            }
        }
        return (best.segment, best.t, best.point, best.d2.squareRoot())
    }

    static func closestOnPolyline(_ pts: [Pt], closed: Bool, to p: Pt)
        -> (segment: Int, t: Double, point: Pt, distance: Double)?
    {
        guard pts.count >= 2 else { return nil }
        let edges = closed ? pts.count : pts.count - 1
        var best: (segment: Int, t: Double, point: Pt, d2: Double)? = nil
        for i in 0..<edges {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t =
                len2 < 1e-12
                ? 0 : min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            let q = lerp(a, b, t)
            let d2 = (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)
            if best == nil || d2 < best!.d2 { best = (i, t, q, d2) }
        }
        return best.map { (segment: $0.segment, t: $0.t, point: $0.point, distance: $0.d2.squareRoot()) }
    }

    /// Closest outline point across an element's editable paths. Nil for
    /// primitives (they carry no anchor-level outline until degraded).
    public static func closestPoint(of element: Element, to p: Pt)
        -> (path: Int, segment: Int, t: Double, point: Pt, distance: Double)?
    {
        switch element {
        case .stroke(let s):
            if let rp = s.refined {
                let hit = closestPoint(on: rp, to: p)
                return (0, hit.segment, hit.t, hit.point, hit.distance)
            }
            return closestOnPolyline(s.points, closed: s.closed, to: p).map {
                (0, $0.segment, $0.t, $0.point, $0.distance)
            }
        case .fill(let f):
            switch f.geometry {
            case .refined(let paths):
                var best: (path: Int, segment: Int, t: Double, point: Pt, distance: Double)? = nil
                for (pi, rp) in paths.enumerated() {
                    let hit = closestPoint(on: rp, to: p)
                    if best == nil || hit.distance < best!.distance {
                        best = (pi, hit.segment, hit.t, hit.point, hit.distance)
                    }
                }
                return best
            case .rings(let rings):
                var best: (path: Int, segment: Int, t: Double, point: Pt, distance: Double)? = nil
                for (ri, ring) in rings.enumerated() {
                    guard let hit = closestOnPolyline(ring, closed: true, to: p) else { continue }
                    if best == nil || hit.distance < best!.distance {
                        best = (ri, hit.segment, hit.t, hit.point, hit.distance)
                    }
                }
                return best
            case .circle, .ellipse, .rect:
                return nil
            }
        }
    }

    /// Insert an anchor on one element at (segment, t) — as reported by
    /// `closestPoint(of:to:)`. The new anchor's index is `segment + 1`.
    /// Returns nil when the geometry cannot take a point (fill primitives).
    public static func insertAnchor(_ element: Element, path: Int, segment: Int, t: Double)
        -> Element?
    {
        switch element {
        case .stroke(var s):
            guard path == 0 else { return nil }
            if let rp = s.refined {
                let split = insertingAnchor(rp, segment: segment, t: t)
                s.refined = split
                s.points = PathRefine.flatten(split)
                return .stroke(s)
            }
            guard s.points.count >= 2, segment >= 0, segment < s.points.count - 1 else {
                return nil
            }
            s.points.insert(
                lerp(s.points[segment], s.points[segment + 1], min(max(t, 0), 1)),
                at: segment + 1)
            return .stroke(s)
        case .fill(var f):
            switch f.geometry {
            case .refined(var paths):
                guard path < paths.count else { return nil }
                paths[path] = insertingAnchor(paths[path], segment: segment, t: t)
                f.geometry = .refined(paths)
                return .fill(f)
            case .rings(var rings):
                guard path < rings.count, rings[path].count >= 2 else { return nil }
                let ring = rings[path]
                let i = min(max(segment, 0), ring.count - 1)
                let next = ring[(i + 1) % ring.count]
                rings[path].insert(lerp(ring[i], next, min(max(t, 0), 1)), at: i + 1)
                f.geometry = .rings(rings)
                return .fill(f)
            case .circle, .ellipse, .rect:
                return nil
            }
        }
    }
}

// MARK: - Colour

extension Editing {
    /// The element's current display colour (a gradient reports its first stop).
    public static func color(of element: Element) -> RGB {
        switch element {
        case .stroke(let s):
            return (s.color.count > 2 ? (s.color[0], s.color[1], s.color[2]) : (0, 0, 0))
        case .fill(let f):
            switch f.paint {
            case .solid(let c):
                return (c.count > 2 ? (c[0], c[1], c[2]) : (0, 0, 0))
            case .linear(let g):
                let c = g.stops.first?.color ?? [0, 0, 0]
                return (c.count > 2 ? (c[0], c[1], c[2]) : (0, 0, 0))
            case .radial(let g):
                let c = g.stops.first?.color ?? [0, 0, 0]
                return (c.count > 2 ? (c[0], c[1], c[2]) : (0, 0, 0))
            }
        }
    }

    /// Recolour an element. Strokes change their line colour; fills become a
    /// solid of the given colour (a recoloured gradient collapses to solid —
    /// predictable, and undo restores the gradient).
    public static func setColor(_ element: Element, to c: RGB) -> Element {
        switch element {
        case .stroke(var s):
            s.color = [c.r, c.g, c.b]
            return .stroke(s)
        case .fill(var f):
            f.paint = .solid([c.r, c.g, c.b])
            return .fill(f)
        }
    }
}

// MARK: - Selection export

extension Editing {
    static func translatedPath(_ rp: RefinedPath, _ dx: Double, _ dy: Double) -> RefinedPath {
        func t(_ p: Pt) -> Pt { Pt(p.x + dx, p.y + dy) }
        var segments: [RefinedSegment] = []
        for seg in rp.segments {
            switch seg {
            case .line(let to): segments.append(.line(to: t(to)))
            case .cubic(let c1, let c2, let to):
                segments.append(.cubic(c1: t(c1), c2: t(c2), to: t(to)))
            case .arc(let c, let r, let sa, let ea, let cw):
                segments.append(
                    .arc(center: t(c), radius: r, startAngle: sa, endAngle: ea, clockwise: cw))
            }
        }
        return RefinedPath(start: t(rp.start), segments: segments, closed: rp.closed)
    }

    /// The element moved by (dx, dy) — all geometry forms supported.
    public static func translated(_ element: Element, dx: Double, dy: Double) -> Element {
        func t(_ p: Pt) -> Pt { Pt(p.x + dx, p.y + dy) }
        switch element {
        case .stroke(var s):
            s.points = s.points.map(t)
            if let rp = s.refined { s.refined = translatedPath(rp, dx, dy) }
            return .stroke(s)
        case .fill(var f):
            switch f.geometry {
            case .rings(let rings):
                f.geometry = .rings(rings.map { $0.map(t) })
            case .refined(let paths):
                f.geometry = .refined(paths.map { translatedPath($0, dx, dy) })
            case .circle(let c, let r):
                f.geometry = .circle(center: t(c), radius: r)
            case .ellipse(let c, let rx, let ry, let rot):
                f.geometry = .ellipse(center: t(c), rx: rx, ry: ry, rotation: rot)
            case .rect(let c, let w, let h, let rot, let cr):
                f.geometry = .rect(center: t(c), w: w, h: h, rotation: rot, cornerRadius: cr)
            }
            // Gradient paints are positioned in user space — move them too.
            switch f.paint {
            case .solid: break
            case .linear(var g):
                g.p0 = t(g.p0)
                g.p1 = t(g.p1)
                f.paint = .linear(g)
            case .radial(var g):
                g.center = t(g.center)
                f.paint = .radial(g)
            }
            return .fill(f)
        }
    }

    /// Bounding box of an element's drawn geometry (stroke width included).
    public static func bounds(of element: Element) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        func eat(_ p: Pt) {
            minX = Swift.min(minX, p.x)
            minY = Swift.min(minY, p.y)
            maxX = Swift.max(maxX, p.x)
            maxY = Swift.max(maxY, p.y)
        }
        switch element {
        case .stroke(let s):
            for p in s.points { eat(p) }
            guard minX <= maxX else { return nil }
            let half = s.width / 2 + 1
            return (minX - half, minY - half, maxX + half, maxY + half)
        case .fill(let f):
            for ring in f.rings {
                for p in ring { eat(p) }
            }
            guard minX <= maxX else { return nil }
            return (minX - 1, minY - 1, maxX + 1, maxY + 1)
        }
    }

    /// A standalone document containing only the given elements, translated to
    /// a tight artboard (small padding). Suitable for copy/export of a selection.
    public static func subDocument(_ doc: VectorDocument, elements indices: [Int])
        -> VectorDocument?
    {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var picked: [Element] = []
        for i in indices.sorted() where i < doc.elements.count {
            let el = doc.elements[i]
            guard let b = bounds(of: el) else { continue }
            minX = Swift.min(minX, b.minX)
            minY = Swift.min(minY, b.minY)
            maxX = Swift.max(maxX, b.maxX)
            maxY = Swift.max(maxY, b.maxY)
            picked.append(el)
        }
        guard !picked.isEmpty, minX <= maxX else { return nil }
        let pad = 2.0
        let ox = minX - pad
        let oy = minY - pad
        var out = VectorDocument(
            width: Int((maxX - minX + 2 * pad).rounded(.up)),
            height: Int((maxY - minY + 2 * pad).rounded(.up)))
        out.elements = picked.map { translated($0, dx: -ox, dy: -oy) }
        return out
    }
}
