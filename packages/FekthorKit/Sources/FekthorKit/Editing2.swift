import Foundation

/// Node editing on Document Model v2. Thin wrappers around the geometry ops
/// in `Editing` (movedPath / cubicized / removingAnchor / …), plus the two
/// v2-specific degrade rules:
/// - primitives expand to `.path` on the first anchor-level edit;
/// - a `transform` bakes into geometry on the first geometry edit (arcs are
///   cubicized first, since affine maps preserve cubics but not arcs).
/// Untouched nodes keep their primitive/transform form for round-trip.
public enum Editing2 {
    public struct Anchor: Equatable, Sendable {
        public var path: Int  // subpath index
        public var index: Int  // 0 = start
        public var position: Pt
    }

    /// Circle/ellipse cubic constant.
    static let kappa = 0.5522847498307936

    // MARK: - Primitive expansion

    /// The node's geometry as typed paths, primitives expanded, transform
    /// applied (baked). Editing always goes through this form.
    public static func bakedPaths(of node: ShapeNode) -> [RefinedPath] {
        var paths = pathify(node.kind)
        if let t = node.transform {
            paths = paths.map { bake($0, t) }
        }
        return paths
    }

    static func pathify(_ kind: ShapeKind) -> [RefinedPath] {
        switch kind {
        case .path(let paths):
            return paths
        case .line(let a, let b):
            return [RefinedPath(start: a, segments: [.line(to: b)], closed: false)]
        case .polyline(let pts):
            guard pts.count >= 2 else { return [] }
            return [
                RefinedPath(
                    start: pts[0], segments: pts.dropFirst().map { .line(to: $0) },
                    closed: false)
            ]
        case .polygon(let pts):
            guard pts.count >= 3 else { return [] }
            return [
                RefinedPath(
                    start: pts[0], segments: pts.dropFirst().map { .line(to: $0) },
                    closed: true)
            ]
        case .rect(let x, let y, let w, let h, let rxOpt, let ryOpt):
            let rx = min(rxOpt ?? ryOpt ?? 0, w / 2)
            let ry = min(ryOpt ?? rxOpt ?? 0, h / 2)
            if rx <= 0.001 || ry <= 0.001 {
                return [
                    RefinedPath(
                        start: Pt(x, y),
                        segments: [
                            .line(to: Pt(x + w, y)), .line(to: Pt(x + w, y + h)),
                            .line(to: Pt(x, y + h)), .line(to: Pt(x, y)),
                        ], closed: true)
                ]
            }
            let kx = kappa * rx
            let ky = kappa * ry
            var segments: [RefinedSegment] = []
            // Start at top-left corner end (x+rx, y), go clockwise.
            segments.append(.line(to: Pt(x + w - rx, y)))
            segments.append(
                .cubic(
                    c1: Pt(x + w - rx + kx, y), c2: Pt(x + w, y + ry - ky),
                    to: Pt(x + w, y + ry)))
            segments.append(.line(to: Pt(x + w, y + h - ry)))
            segments.append(
                .cubic(
                    c1: Pt(x + w, y + h - ry + ky), c2: Pt(x + w - rx + kx, y + h),
                    to: Pt(x + w - rx, y + h)))
            segments.append(.line(to: Pt(x + rx, y + h)))
            segments.append(
                .cubic(
                    c1: Pt(x + rx - kx, y + h), c2: Pt(x, y + h - ry + ky),
                    to: Pt(x, y + h - ry)))
            segments.append(.line(to: Pt(x, y + ry)))
            segments.append(
                .cubic(c1: Pt(x, y + ry - ky), c2: Pt(x + rx - kx, y), to: Pt(x + rx, y)))
            return [RefinedPath(start: Pt(x + rx, y), segments: segments, closed: true)]
        case .circle(let c, let r):
            return [ellipsePath(center: c, rx: r, ry: r)]
        case .ellipse(let c, let rx, let ry):
            return [ellipsePath(center: c, rx: rx, ry: ry)]
        }
    }

    static func ellipsePath(center c: Pt, rx: Double, ry: Double) -> RefinedPath {
        let kx = kappa * rx
        let ky = kappa * ry
        let start = Pt(c.x + rx, c.y)
        let segments: [RefinedSegment] = [
            .cubic(
                c1: Pt(c.x + rx, c.y + ky), c2: Pt(c.x + kx, c.y + ry), to: Pt(c.x, c.y + ry)),
            .cubic(
                c1: Pt(c.x - kx, c.y + ry), c2: Pt(c.x - rx, c.y + ky), to: Pt(c.x - rx, c.y)),
            .cubic(
                c1: Pt(c.x - rx, c.y - ky), c2: Pt(c.x - kx, c.y - ry), to: Pt(c.x, c.y - ry)),
            .cubic(
                c1: Pt(c.x + kx, c.y - ry), c2: Pt(c.x + rx, c.y - ky), to: start),
        ]
        return RefinedPath(start: start, segments: segments, closed: true)
    }

    /// Apply an affine transform to a path. Arcs are cubicized first — an
    /// affine map preserves cubics exactly but arcs only under similarity.
    static func bake(_ rp: RefinedPath, _ t: TransformValue) -> RefinedPath {
        let path = Editing.cubicized(rp)
        func map(_ p: Pt) -> Pt { t.apply(p) }
        var segments: [RefinedSegment] = []
        for seg in path.segments {
            switch seg {
            case .line(let to): segments.append(.line(to: map(to)))
            case .cubic(let c1, let c2, let to):
                segments.append(.cubic(c1: map(c1), c2: map(c2), to: map(to)))
            case .arc:
                break  // unreachable post-cubicize
            }
        }
        return RefinedPath(start: map(path.start), segments: segments, closed: path.closed)
    }

    /// The node with primitives expanded and transform baked — the editable
    /// form every mutation below starts from.
    public static func editable(_ node: ShapeNode) -> ShapeNode {
        var out = node
        out.kind = .path(bakedPaths(of: node))
        out.transform = nil
        return out
    }

    // MARK: - Anchors & handles

    public static func anchors(of node: ShapeNode) -> [Anchor] {
        var out: [Anchor] = []
        for (pi, rp) in bakedPaths(of: node).enumerated() {
            for a in Editing.pathAnchors(rp, path: pi) {
                out.append(Anchor(path: a.path, index: a.index, position: a.position))
            }
        }
        return out
    }

    public static func moveAnchor(_ node: ShapeNode, path: Int, anchor: Int, to: Pt) -> ShapeNode {
        var out = editable(node)
        guard case .path(var paths) = out.kind, path < paths.count else { return node }
        let radii = paths[path].cornerRadii  // moving a point keeps anchor indices
        var moved = Editing.movedPath(paths[path], anchor: anchor, to: to)
        moved.cornerRadii = radii
        paths[path] = moved
        out.kind = .path(paths)
        return out
    }

    public struct Handle: Equatable, Sendable {
        public var path: Int
        public var segment: Int
        public var kind: Editing.HandleKind
        public var position: Pt
        public var anchor: Pt
    }

    public static func handles(of node: ShapeNode, path: Int, anchor: Int) -> [Handle] {
        let paths = bakedPaths(of: node)
        guard path < paths.count else { return [] }
        let cubed = Editing.cubicized(paths[path])
        let n = cubed.segments.count
        guard n > 0 else { return [] }
        let anchorPos: Pt =
            anchor == 0
            ? cubed.start
            : (anchor - 1 < n ? cubed.segments[anchor - 1].endPoint : cubed.start)
        var out: [Handle] = []
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

    public static func moveHandle(
        _ node: ShapeNode, path: Int, segment: Int, kind: Editing.HandleKind, to: Pt,
        mirror: Bool = false
    ) -> ShapeNode {
        var out = editable(node)
        guard case .path(var paths) = out.kind, path < paths.count else { return node }
        // Delegate to the element-level op through a temporary stroke wrapper
        // (the geometry rules live in one place).
        let wrapped = Element.stroke(
            StrokePath(
                id: "", color: (0, 0, 0), width: 1, closed: paths[path].closed, points: [],
                refined: paths[path]))
        let moved = Editing.moveHandle(
            wrapped, path: 0, segment: segment, kind: kind, to: to, mirror: mirror)
        guard case .stroke(let s) = moved, let rp = s.refined else { return node }
        paths[path] = rp
        out.kind = .path(paths)
        return out
    }

    /// Remove an anchor (end anchors shorten open subpaths; interior anchors
    /// merge their segments). Returns nil when the subpath is at its minimum.
    public static func removeAnchor(_ node: ShapeNode, path: Int, anchor: Int) -> ShapeNode? {
        var out = editable(node)
        guard case .path(var paths) = out.kind, path < paths.count else { return nil }
        guard let removed = Editing.removingAnchor(paths[path], anchor: anchor) else {
            return nil
        }
        paths[path] = removed
        out.kind = .path(paths)
        return out
    }

    /// Split a subpath segment at `t`, adding one anchor without changing the
    /// drawn geometry. Primitives degrade to `.path` (via `editable`) like
    /// every other anchor-level edit. The new anchor's index is `segment + 1`.
    public static func insertAnchor(_ node: ShapeNode, path: Int, segment: Int, t: Double)
        -> ShapeNode
    {
        var out = editable(node)
        guard case .path(var paths) = out.kind, path < paths.count else { return node }
        paths[path] = Editing.insertingAnchor(paths[path], segment: segment, t: t)
        out.kind = .path(paths)
        return out
    }

    /// Closest outline point across the node's (baked) subpaths — the hit
    /// test behind ⌘-click "add point". Segment/t index into the cubicized
    /// subpath, matching `insertAnchor`.
    public static func closestPoint(of node: ShapeNode, to p: Pt)
        -> (path: Int, segment: Int, t: Double, point: Pt, distance: Double)?
    {
        var best: (path: Int, segment: Int, t: Double, point: Pt, distance: Double)? = nil
        for (pi, rp) in bakedPaths(of: node).enumerated() {
            let hit = Editing.closestPoint(on: rp, to: p)
            if best == nil || hit.distance < best!.distance {
                best = (pi, hit.segment, hit.t, hit.point, hit.distance)
            }
        }
        return best
    }

    // MARK: - Whole-node ops

    /// Translate WITHOUT degrading: primitives shift their parameters, paths
    /// shift their points, an existing transform gains the offset.
    public static func translated(_ node: ShapeNode, dx: Double, dy: Double) -> ShapeNode {
        var out = node
        if var t = out.transform {
            t.matrix[4] += dx
            t.matrix[5] += dy
            t.raw = "matrix(\(t.matrix.map { SVGNum.text($0) }.joined(separator: " ")))"
            out.transform = t
            return out
        }
        func s(_ p: Pt) -> Pt { Pt(p.x + dx, p.y + dy) }
        switch out.kind {
        case .path(let paths):
            out.kind = .path(paths.map { Editing.translatedPath($0, dx, dy) })
        case .line(let a, let b):
            out.kind = .line(s(a), s(b))
        case .polyline(let pts):
            out.kind = .polyline(pts.map(s))
        case .polygon(let pts):
            out.kind = .polygon(pts.map(s))
        case .rect(let x, let y, let w, let h, let rx, let ry):
            out.kind = .rect(x: x + dx, y: y + dy, width: w, height: h, rx: rx, ry: ry)
        case .circle(let c, let r):
            out.kind = .circle(center: s(c), r: r)
        case .ellipse(let c, let rx, let ry):
            out.kind = .ellipse(center: s(c), rx: rx, ry: ry)
        }
        return out
    }

    // MARK: - Whole-node scale / rotate

    /// The matrix for scale(sx, sy) about a fixed point:
    /// translate(c) · scale · translate(-c).
    static func scaleTransform(sx: Double, sy: Double, around c: Pt) -> TransformValue {
        let m = [sx, 0, 0, sy, c.x - sx * c.x, c.y - sy * c.y]
        return TransformValue(
            raw: "matrix(" + m.map { SVGNum.text($0) }.joined(separator: " ") + ")", matrix: m)
    }

    /// Scale a node about a fixed point. Degrade rules:
    /// - a node already carrying a `transform` keeps its kind and the scale
    ///   composes onto the transform (outer), mirroring `translated`;
    /// - rect stays rect (an axis-aligned scale maps rects to rects; corner
    ///   radii scale per axis), circle stays circle under uniform scale and
    ///   becomes an ellipse otherwise, ellipse stays ellipse,
    ///   line/polyline/polygon map their points;
    /// - paths map their control points (arcs cubicized first, like `bake` —
    ///   affine maps preserve cubics but not arcs).
    public static func scaled(_ node: ShapeNode, sx: Double, sy: Double, around c: Pt)
        -> ShapeNode
    {
        var out = node
        let t = scaleTransform(sx: sx, sy: sy, around: c)
        if let existing = out.transform {
            out.transform = t.concatenating(existing)
            return out
        }
        func map(_ p: Pt) -> Pt { t.apply(p) }
        switch out.kind {
        case .path(let paths):
            out.kind = .path(paths.map { bake($0, t) })
        case .line(let a, let b):
            out.kind = .line(map(a), map(b))
        case .polyline(let pts):
            out.kind = .polyline(pts.map(map))
        case .polygon(let pts):
            out.kind = .polygon(pts.map(map))
        case .rect(let x, let y, let w, let h, let rx, let ry):
            let p0 = map(Pt(x, y))
            let p1 = map(Pt(x + w, y + h))
            let ax = abs(sx)
            let ay = abs(sy)
            var nrx = rx.map { $0 * ax }
            var nry = ry.map { $0 * ay }
            // A single declared radius means rx == ry (SVG default); a
            // non-uniform scale must split it into both.
            if abs(ax - ay) > 1e-9 {
                if nrx == nil, let base = ry { nrx = base * ax }
                if nry == nil, let base = rx { nry = base * ay }
            }
            out.kind = .rect(
                x: min(p0.x, p1.x), y: min(p0.y, p1.y),
                width: abs(p1.x - p0.x), height: abs(p1.y - p0.y), rx: nrx, ry: nry)
        case .circle(let center, let r):
            if abs(abs(sx) - abs(sy)) < 1e-9 {
                out.kind = .circle(center: map(center), r: r * abs(sx))
            } else {
                out.kind = .ellipse(center: map(center), rx: r * abs(sx), ry: r * abs(sy))
            }
        case .ellipse(let center, let rx, let ry):
            out.kind = .ellipse(center: map(center), rx: rx * abs(sx), ry: ry * abs(sy))
        }
        return out
    }

    /// Rotate a node about a fixed point (radians; positive is clockwise on
    /// screen with SVG's y-down axis). Degrade rules:
    /// - a node already carrying a `transform` keeps its kind and the
    ///   rotation composes onto the transform (outer);
    /// - circle stays circle (its centre orbits), line/polyline/polygon map
    ///   their points, paths map control points (arcs cubicized first);
    /// - rect and ellipse keep their primitive and GAIN a
    ///   `rotate(deg cx cy)` transform — the Model2Bridge convention for
    ///   rotated primitives.
    public static func rotated(_ node: ShapeNode, by radians: Double, around c: Pt) -> ShapeNode {
        guard let t = Model2Bridge.rotationTransform(radians, about: c) else { return node }
        var out = node
        if let existing = out.transform {
            out.transform = t.concatenating(existing)
            return out
        }
        func map(_ p: Pt) -> Pt { t.apply(p) }
        switch out.kind {
        case .path(let paths):
            out.kind = .path(paths.map { bake($0, t) })
        case .line(let a, let b):
            out.kind = .line(map(a), map(b))
        case .polyline(let pts):
            out.kind = .polyline(pts.map(map))
        case .polygon(let pts):
            out.kind = .polygon(pts.map(map))
        case .rect, .ellipse:
            out.transform = t
        case .circle(let center, let r):
            out.kind = .circle(center: map(center), r: r)
        }
        return out
    }

    /// Tight geometric bounds of the node's baked outline (curves flattened),
    /// or nil for empty geometry. Drives the selection box and the live
    /// w×h readout.
    public static func bounds(of node: ShapeNode)
        -> (minX: Double, minY: Double, maxX: Double, maxY: Double)?
    {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for rp in bakedPaths(of: node) {
            for p in PathRefine.flatten(rp) {
                minX = Swift.min(minX, p.x)
                minY = Swift.min(minY, p.y)
                maxX = Swift.max(maxX, p.x)
                maxY = Swift.max(maxY, p.y)
            }
        }
        guard minX <= maxX else { return nil }
        return (minX, minY, maxX, maxY)
    }
}
