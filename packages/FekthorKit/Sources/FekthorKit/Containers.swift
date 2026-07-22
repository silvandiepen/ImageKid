import Foundation

// MARK: - Containers (P2)
//
// A container is a normal SVG in the workspace (badge, circle backdrop,
// app-icon frame) plus a slot rect stored in the workfile defining where
// content goes. Content icons declare container memberships; export composes
// the matrix — icon A in containers X, Y, Z produces A-X.svg, A-Y.svg,
// A-Z.svg. Editing the container once updates every composed export.
//
// Composition is a clean group wrap: the content document's nodes are placed
// inside a single `<g transform="translate(…) scale(…)">` mapping the
// content's viewBox into the slot rect. No geometry or style is baked.

/// How content is scaled into a container slot. Parsed forgivingly from the
/// workfile's `ContainerSlot.fit` string; unknown or missing values fall back
/// to `.contain`.
public enum FitRule: String, Equatable, Sendable {
    /// Scale uniformly so the content fits entirely inside the slot (default).
    case contain
    /// Scale uniformly so the content fills the slot (may overflow it).
    case cover
    /// Scale non-uniformly so the content exactly fills the slot.
    case stretch
    /// No scaling; the content is centered in the slot at natural size.
    case center

    /// Forgiving parse: case- and whitespace-insensitive, common synonyms
    /// accepted (`fill` → stretch, `none` → center). Anything else — including
    /// nil — is `.contain`.
    public static func parse(_ raw: String?) -> FitRule {
        let name = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch name {
        case "cover": return .cover
        case "stretch", "fill": return .stretch
        case "center", "none": return .center
        default: return .contain
        }
    }
}

public enum Containers {
    /// Typed failure for matrix export.
    public enum ExportError: Error, Equatable, Sendable {
        /// Memberships referenced container names with no known container
        /// document/slot. Names are sorted and de-duplicated.
        case unknownContainers([String])
    }

    // MARK: Compose

    /// Compose a content icon into a container document.
    ///
    /// The result carries the container's viewBox and root attributes; its
    /// nodes are the container's nodes first, then ONE group wrapping the
    /// content's nodes with a `translate(…) scale(…)` transform mapping the
    /// content's viewBox into the slot rect per the fit rule (centered within
    /// the slot on the non-dominant axis). Content root-level attributes are
    /// dropped; content geometry and styles are untouched. Node ids are
    /// reassigned sequentially in document order (matching what a re-read of
    /// the written file would assign), so the operation is deterministic.
    public static func compose(
        content: GraphicDocument, into container: GraphicDocument, slot: Workfile.ContainerSlot
    ) -> GraphicDocument {
        let transform = slotTransform(contentViewBox: content.viewBox, slot: slot)
        let wrapper = GroupNode(id: 0, transform: transform, children: content.nodes)
        var out = GraphicDocument(
            viewBox: container.viewBox, rootAttributes: container.rootAttributes,
            hadXMLDeclaration: container.hadXMLDeclaration,
            nodes: container.nodes + [.group(wrapper)])
        renumber(&out.nodes)
        return out
    }

    /// The group transform mapping `contentViewBox` into the slot rect per
    /// the slot's fit rule. Nil when the mapping is the identity. The raw
    /// text and the matrix agree (same convention as SVGReader.parseTransform:
    /// matrix is [a, b, c, d, tx, ty], translate-then-scale order).
    public static func slotTransform(
        contentViewBox cb: ViewBox, slot: Workfile.ContainerSlot
    ) -> TransformValue? {
        let fit = FitRule.parse(slot.fit)
        var sx = 1.0
        var sy = 1.0
        if cb.width > 0, cb.height > 0 {
            switch fit {
            case .contain:
                let s = min(slot.width / cb.width, slot.height / cb.height)
                sx = s
                sy = s
            case .cover:
                let s = max(slot.width / cb.width, slot.height / cb.height)
                sx = s
                sy = s
            case .stretch:
                sx = slot.width / cb.width
                sy = slot.height / cb.height
            case .center:
                break
            }
        }
        // Center within the slot on the non-dominant axis (a no-op for
        // stretch, where both axes fill exactly).
        let tx = slot.x + (slot.width - cb.width * sx) / 2 - cb.minX * sx
        let ty = slot.y + (slot.height - cb.height * sy) / 2 - cb.minY * sy

        var parts: [String] = []
        if tx != 0 || ty != 0 {
            parts.append("translate(\(num(tx)) \(num(ty)))")
        }
        if sx != 1 || sy != 1 {
            parts.append(sx == sy ? "scale(\(num(sx)))" : "scale(\(num(sx)) \(num(sy)))")
        }
        guard !parts.isEmpty else { return nil }
        return TransformValue(
            raw: parts.joined(separator: " "), matrix: [sx, 0, 0, sy, tx, ty])
    }

    // MARK: Matrix export

    /// Compose every icon into every container it belongs to. Output is
    /// deterministic: icons sorted by name, then each icon's containers
    /// sorted by name (duplicates collapsed); file names are
    /// `{icon}-{container}.svg`. Membership entries whose icon has no
    /// document in `icons` are skipped; membership container names with no
    /// entry in `containers` throw `ExportError.unknownContainers`.
    public static func matrixExports(
        icons: [String: GraphicDocument],
        containers: [String: (GraphicDocument, Workfile.ContainerSlot)],
        memberships: [String: [String]]
    ) throws -> [(fileName: String, doc: GraphicDocument)] {
        var unknown = Set<String>()
        for names in memberships.values {
            for name in names where containers[name] == nil {
                unknown.insert(name)
            }
        }
        guard unknown.isEmpty else {
            throw ExportError.unknownContainers(unknown.sorted())
        }
        var out: [(fileName: String, doc: GraphicDocument)] = []
        for icon in memberships.keys.sorted() {
            guard let contentDoc = icons[icon] else { continue }
            for name in Set(memberships[icon] ?? []).sorted() {
                let (containerDoc, slot) = containers[name]!
                out.append(
                    (
                        fileName: "\(icon)-\(name).svg",
                        doc: compose(content: contentDoc, into: containerDoc, slot: slot)
                    ))
            }
        }
        return out
    }

    // MARK: Helpers

    /// Reassign node ids sequentially in document order (groups before their
    /// children), matching SVGReader's assignment on re-read.
    private static func renumber(_ nodes: inout [GraphicNode]) {
        var next = 0
        func walk(_ nodes: inout [GraphicNode]) {
            for i in nodes.indices {
                switch nodes[i] {
                case .shape(var s):
                    s.id = next
                    next += 1
                    nodes[i] = .shape(s)
                case .group(var g):
                    g.id = next
                    next += 1
                    walk(&g.children)
                    nodes[i] = .group(g)
                case .raw(var r):
                    r.id = next
                    next += 1
                    nodes[i] = .raw(r)
                }
            }
        }
        walk(&nodes)
    }

    /// Transform number text in corpus style (see `SVGNum`) but with up to
    /// 6 decimals so scale factors keep render precision: trailing zeros
    /// trimmed, leading zero dropped (`.5`), locale-safe (`String(format:)`
    /// never localizes the decimal point).
    private static func num(_ v: Double) -> String {
        var r = v
        if r == 0 { r = 0 }  // avoid "-0"
        if r == r.rounded(), abs(r) < 1e15 {
            return String(Int(r))
        }
        var s = String(format: "%.6f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        if s.hasPrefix("0.") { s.removeFirst() }
        if s.hasPrefix("-0.") { s = "-" + s.dropFirst(2) }
        return s
    }
}
