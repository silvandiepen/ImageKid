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
        paths[path] = Editing.movedPath(paths[path], anchor: anchor, to: to)
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
}
