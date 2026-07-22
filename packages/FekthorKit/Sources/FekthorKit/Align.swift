import Foundation

// MARK: - Align & distribute on GraphicDocument
//
// Pure ops: every function returns a new document. Nodes move via
// `Editing2.translated` (shapes) or a composed translation transform
// (groups), so primitives stay primitives and untouched nodes round-trip
// verbatim. Bounds are document-space (`Editing2.bounds` of the baked
// outline, composed through every ancestor group transform), matching the
// selection box the editor shows.

/// An alignment target edge/axis, in document coordinates (y down).
public enum AlignEdge: Sendable {
    case left
    case centerX
    case right
    case top
    case centerY
    case bottom
}

/// The axis along which `Align.distribute` equalises gaps.
public enum DistributeAxis: Sendable {
    case horizontal
    case vertical
}

public enum Align {
    public typealias Bounds = (minX: Double, minY: Double, maxX: Double, maxY: Double)

    // MARK: - Public ops

    /// Align each selected node's bounds to the selection's collective
    /// bounds edge. Only topmost selected nodes move (a selected child of a
    /// selected group would otherwise move twice). Nodes without geometry
    /// (raw fragments, empty groups) are ignored. Deterministic: nodes are
    /// visited in document order.
    public static func align(_ ids: Set<Int>, edge: AlignEdge, in doc: GraphicDocument)
        -> GraphicDocument
    {
        let items = topmostSelected(ids, in: doc)
        guard !items.isEmpty else { return doc }
        let target = union(items.map(\.bounds))
        return applying(deltas(items, toward: target, edge: edge), to: doc)
    }

    /// Align each selected node to the artboard (viewBox) edge — the
    /// single-node variant of `align`, which needs no collective bounds.
    public static func alignToArtboard(_ ids: Set<Int>, edge: AlignEdge, in doc: GraphicDocument)
        -> GraphicDocument
    {
        let items = topmostSelected(ids, in: doc)
        guard !items.isEmpty else { return doc }
        let vb = doc.viewBox
        let target: Bounds = (vb.minX, vb.minY, vb.minX + vb.width, vb.minY + vb.height)
        return applying(deltas(items, toward: target, edge: edge), to: doc)
    }

    /// Distribute the selected nodes so the gaps BETWEEN their bounds are
    /// equal along `axis`. Needs at least 3 movable nodes; the outermost two
    /// (after sorting by position) stay fixed. Overlapping nodes produce a
    /// negative gap — still equal.
    public static func distribute(_ ids: Set<Int>, axis: DistributeAxis, in doc: GraphicDocument)
        -> GraphicDocument
    {
        var items = topmostSelected(ids, in: doc)
        guard items.count >= 3 else { return doc }
        func lo(_ b: Bounds) -> Double { axis == .horizontal ? b.minX : b.minY }
        func hi(_ b: Bounds) -> Double { axis == .horizontal ? b.maxX : b.maxY }
        items.sort {
            let (a, b) = ($0.bounds, $1.bounds)
            if lo(a) != lo(b) { return lo(a) < lo(b) }
            if hi(a) != hi(b) { return hi(a) < hi(b) }
            return $0.id < $1.id
        }
        let first = items.first!.bounds
        let last = items.last!.bounds
        let span = hi(last) - lo(first)
        let totalSize = items.reduce(0.0) { $0 + (hi($1.bounds) - lo($1.bounds)) }
        let gap = (span - totalSize) / Double(items.count - 1)
        var moves: [Int: (dx: Double, dy: Double)] = [:]
        var cursor = lo(first)
        for item in items {
            let size = hi(item.bounds) - lo(item.bounds)
            let d = cursor - lo(item.bounds)
            if d != 0 {
                moves[item.id] = axis == .horizontal ? (d, 0) : (0, d)
            }
            cursor += size + gap
        }
        return applying(moves, to: doc)
    }

    /// Document-space bounds of a node anywhere in the tree (group bounds
    /// are the union of their children, composed through transforms), or nil
    /// for raw fragments / empty geometry.
    public static func bounds(of id: Int, in doc: GraphicDocument) -> Bounds? {
        topmostSelected([id], in: doc).first?.bounds
    }

    // MARK: - Bounds collection

    struct Item {
        var id: Int
        var bounds: Bounds
        /// Composed transform of every ancestor group (nil = identity), used
        /// to convert a document-space delta into the node's parent space.
        var ancestor: TransformValue?
    }

    /// Selected nodes in document order, skipping descendants of selected
    /// nodes and anything without geometry.
    static func topmostSelected(_ ids: Set<Int>, in doc: GraphicDocument) -> [Item] {
        var out: [Item] = []
        func walk(_ nodes: [GraphicNode], ancestor: TransformValue?) {
            for node in nodes {
                if ids.contains(node.id) {
                    if let b = nodeBounds(node, ancestor: ancestor) {
                        out.append(Item(id: node.id, bounds: b, ancestor: ancestor))
                    }
                    continue  // topmost wins; do not descend
                }
                if case .group(let g) = node {
                    walk(g.children, ancestor: TransformValue.composed(ancestor, g.transform))
                }
            }
        }
        walk(doc.nodes, ancestor: nil)
        return out
    }

    /// Document-space bounds of a node under an accumulated ancestor
    /// transform. Shapes bake `ancestor · own transform` through
    /// `Editing2.bounds`; groups union their children.
    static func nodeBounds(_ node: GraphicNode, ancestor: TransformValue?) -> Bounds? {
        switch node {
        case .raw:
            return nil
        case .shape(var s):
            s.transform = TransformValue.composed(ancestor, s.transform)
            return Editing2.bounds(of: s)
        case .group(let g):
            let inner = TransformValue.composed(ancestor, g.transform)
            var acc: Bounds? = nil
            for child in g.children {
                guard let b = nodeBounds(child, ancestor: inner) else { continue }
                acc = acc.map { union([$0, b]) } ?? b
            }
            return acc
        }
    }

    static func union(_ bounds: [Bounds]) -> Bounds {
        var out = bounds[0]
        for b in bounds.dropFirst() {
            out = (
                Swift.min(out.minX, b.minX), Swift.min(out.minY, b.minY),
                Swift.max(out.maxX, b.maxX), Swift.max(out.maxY, b.maxY)
            )
        }
        return out
    }

    // MARK: - Deltas & application

    /// Per-node document-space delta that brings its bounds onto `target`'s
    /// `edge`.
    static func deltas(_ items: [Item], toward target: Bounds, edge: AlignEdge)
        -> [Int: (dx: Double, dy: Double)]
    {
        var out: [Int: (dx: Double, dy: Double)] = [:]
        for item in items {
            let b = item.bounds
            var dx = 0.0
            var dy = 0.0
            switch edge {
            case .left: dx = target.minX - b.minX
            case .centerX: dx = (target.minX + target.maxX) / 2 - (b.minX + b.maxX) / 2
            case .right: dx = target.maxX - b.maxX
            case .top: dy = target.minY - b.minY
            case .centerY: dy = (target.minY + target.maxY) / 2 - (b.minY + b.maxY) / 2
            case .bottom: dy = target.maxY - b.maxY
            }
            if dx != 0 || dy != 0 { out[item.id] = (dx, dy) }
        }
        return out
    }

    /// Apply document-space translations to the tree. The delta converts to
    /// each node's parent space through the inverse of the ancestor linear
    /// part (ancestors are usually identity or pure translation, where the
    /// conversion is exact). Shapes translate via `Editing2.translated`
    /// (primitives stay primitives); groups compose a translation onto their
    /// transform so children are untouched.
    static func applying(_ moves: [Int: (dx: Double, dy: Double)], to doc: GraphicDocument)
        -> GraphicDocument
    {
        guard !moves.isEmpty else { return doc }
        var out = doc
        func walk(_ nodes: inout [GraphicNode], ancestor: TransformValue?) {
            for i in nodes.indices {
                let node = nodes[i]
                if let d = moves[node.id],
                    let local = toParentSpace(dx: d.dx, dy: d.dy, ancestor: ancestor)
                {
                    switch node {
                    case .raw:
                        break
                    case .shape(let s):
                        nodes[i] = .shape(Editing2.translated(s, dx: local.dx, dy: local.dy))
                    case .group(var g):
                        g.transform = TransformValue.composed(
                            translation(local.dx, local.dy), g.transform)
                        nodes[i] = .group(g)
                    }
                    continue
                }
                if case .group(var g) = node {
                    walk(&g.children, ancestor: TransformValue.composed(ancestor, g.transform))
                    nodes[i] = .group(g)
                }
            }
        }
        walk(&out.nodes, ancestor: nil)
        return out
    }

    /// A document-space delta expressed in the coordinate space under
    /// `ancestor` (inverse of the 2×2 linear part; translation components do
    /// not affect deltas). Nil when the ancestor matrix is singular.
    static func toParentSpace(dx: Double, dy: Double, ancestor: TransformValue?)
        -> (dx: Double, dy: Double)?
    {
        guard let m = ancestor?.matrix else { return (dx, dy) }
        let det = m[0] * m[3] - m[1] * m[2]
        guard abs(det) > 1e-12 else { return nil }
        return ((m[3] * dx - m[2] * dy) / det, (m[0] * dy - m[1] * dx) / det)
    }

    static func translation(_ dx: Double, _ dy: Double) -> TransformValue {
        let m = [1.0, 0, 0, 1, dx, dy]
        return TransformValue(
            raw: "matrix(" + m.map { SVGNum.text($0) }.joined(separator: " ") + ")", matrix: m)
    }
}
