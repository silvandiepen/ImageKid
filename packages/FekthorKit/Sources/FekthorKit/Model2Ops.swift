import Foundation

// MARK: - Structural ops on GraphicDocument (z-order, group/ungroup)
//
// Nodes render in array order (later = on top), so z-order is pure sibling
// reordering. Grouping wraps sibling nodes in a GroupNode; ungrouping
// dissolves a group in place, composing its transform/style onto the freed
// children so nothing moves on screen — correct over clever.

extension TransformValue {
    /// This transform applied AFTER `inner` (SVG list order: `outer inner`).
    public func concatenating(_ inner: TransformValue) -> TransformValue {
        let o = matrix
        let i = inner.matrix
        let m = [
            o[0] * i[0] + o[2] * i[1],
            o[1] * i[0] + o[3] * i[1],
            o[0] * i[2] + o[2] * i[3],
            o[1] * i[2] + o[3] * i[3],
            o[0] * i[4] + o[2] * i[5] + o[4],
            o[1] * i[4] + o[3] * i[5] + o[5],
        ]
        return TransformValue(
            raw: "matrix(" + m.map { SVGNum.text($0) }.joined(separator: " ") + ")", matrix: m)
    }

    /// Compose two optional transforms (either may be absent).
    public static func composed(_ outer: TransformValue?, _ inner: TransformValue?)
        -> TransformValue?
    {
        guard let outer else { return inner }
        guard let inner else { return outer }
        return outer.concatenating(inner)
    }
}

extension GraphicDocument {
    // MARK: Z-order

    /// Move every selected node one step later in its sibling array (drawn
    /// later = on top). Contiguous selected runs keep their relative order.
    public mutating func bringForward(_ ids: Set<Int>) {
        Self.eachSiblingArray(&nodes) { arr in
            guard arr.count > 1 else { return }
            var i = arr.count - 2
            while i >= 0 {
                if ids.contains(arr[i].id), !ids.contains(arr[i + 1].id) {
                    arr.swapAt(i, i + 1)
                }
                i -= 1
            }
        }
    }

    /// Move every selected node one step earlier in its sibling array.
    public mutating func sendBackward(_ ids: Set<Int>) {
        Self.eachSiblingArray(&nodes) { arr in
            guard arr.count > 1 else { return }
            for i in 1..<arr.count where ids.contains(arr[i].id) && !ids.contains(arr[i - 1].id) {
                arr.swapAt(i, i - 1)
            }
        }
    }

    /// Move the selected nodes to the end of their sibling array (topmost),
    /// preserving their relative order.
    public mutating func bringToFront(_ ids: Set<Int>) {
        Self.eachSiblingArray(&nodes) { arr in
            let picked = arr.filter { ids.contains($0.id) }
            guard !picked.isEmpty else { return }
            arr = arr.filter { !ids.contains($0.id) } + picked
        }
    }

    /// Move the selected nodes to the start of their sibling array (bottom),
    /// preserving their relative order.
    public mutating func sendToBack(_ ids: Set<Int>) {
        Self.eachSiblingArray(&nodes) { arr in
            let picked = arr.filter { ids.contains($0.id) }
            guard !picked.isEmpty else { return }
            arr = picked + arr.filter { !ids.contains($0.id) }
        }
    }

    /// Apply `body` to the root array and every group's children (recursive).
    static func eachSiblingArray(
        _ nodes: inout [GraphicNode], _ body: (inout [GraphicNode]) -> Void
    ) {
        body(&nodes)
        for i in nodes.indices {
            if case .group(var g) = nodes[i] {
                eachSiblingArray(&g.children, body)
                nodes[i] = .group(g)
            }
        }
    }

    // MARK: Group

    /// Wrap the selected SIBLING nodes in a new GroupNode placed where the
    /// topmost selected node was; the children keep their document order.
    /// Only the first sibling array containing any selected id participates
    /// (selections spanning parents cannot group without reparenting).
    /// Returns the new group's id, or nil when nothing grouped.
    public mutating func groupNodes(_ ids: Set<Int>) -> Int? {
        guard !ids.isEmpty else { return nil }
        let gid = nextNodeID
        var grouped = false
        func attempt(_ arr: inout [GraphicNode]) -> Bool {
            let selIdx = arr.indices.filter { ids.contains(arr[$0].id) }
            if selIdx.isEmpty {
                for i in arr.indices {
                    if case .group(var g) = arr[i] {
                        if attempt(&g.children) {
                            arr[i] = .group(g)
                            return true
                        }
                    }
                }
                return false
            }
            let top = selIdx.max()!
            let group = GroupNode(id: gid, children: selIdx.map { arr[$0] })
            var out: [GraphicNode] = []
            for (i, n) in arr.enumerated() {
                if ids.contains(n.id) {
                    if i == top { out.append(.group(group)) }
                    continue
                }
                out.append(n)
            }
            arr = out
            grouped = true
            return true
        }
        _ = attempt(&nodes)
        return grouped ? gid : nil
    }

    // MARK: Ungroup

    /// Dissolve each selected group in place: its children take its spot in
    /// the parent's order and inherit the group's transform (composed onto
    /// theirs) and inheritable style declarations, so rendering is unchanged.
    /// Returns the ids of the freed children.
    public mutating func ungroupNodes(_ ids: Set<Int>) -> Set<Int> {
        var freed: Set<Int> = []
        func walk(_ arr: inout [GraphicNode]) {
            var out: [GraphicNode] = []
            for n in arr {
                if case .group(let g) = n, ids.contains(g.id) {
                    for child in g.children {
                        out.append(Self.inheriting(child, from: g))
                        freed.insert(child.id)
                    }
                } else if case .group(var g) = n {
                    walk(&g.children)
                    out.append(.group(g))
                } else {
                    out.append(n)
                }
            }
            arr = out
        }
        walk(&nodes)
        return freed
    }

    /// A child leaving a dissolved group: transforms compose (group first),
    /// inheritable style declarations flow down where the child is silent,
    /// and opacity multiplies (SVG group opacity semantics, approximated
    /// per-child).
    static func inheriting(_ node: GraphicNode, from g: GroupNode) -> GraphicNode {
        switch node {
        case .raw:
            return node  // defs/style fragments: nothing to inherit
        case .shape(var s):
            s.transform = TransformValue.composed(g.transform, s.transform)
            s.style = inheritedStyle(parent: g.style, child: s.style)
            return .shape(s)
        case .image(var i):
            i.transform = TransformValue.composed(g.transform, i.transform)
            i.style = inheritedStyle(parent: g.style, child: i.style)
            return .image(i)
        case .group(var child):
            child.transform = TransformValue.composed(g.transform, child.transform)
            child.style = inheritedStyle(parent: g.style, child: child.style)
            return .group(child)
        }
    }

    static func inheritedStyle(parent: Style, child: Style) -> Style {
        var out = child
        var inherited: [StyleDeclaration] = []
        for d in parent.declarations {
            if d.name == "opacity" {
                if case .number(let po, _) = d.value {
                    out.opacity = (child.opacity ?? 1) * po
                }
            } else if child.value(of: d.name) == nil {
                inherited.append(d)
            }
        }
        out.declarations = inherited + out.declarations
        return out
    }
}
