import Foundation

/// A workspace-level graphic style: a set of CSS declarations under a name
/// that doubles as the SVG class binding it to nodes (`name` is the class).
///
/// Stored in the workfile (`Workfile.namedStyles`); the SVGs stay fully
/// self-contained because applying a style writes its declarations INLINE —
/// the class attribute is only the binding marker that lets later edits to
/// the style find and rewrite its nodes.
public struct NamedStyle: Codable, Equatable, Sendable {
    /// Style name; also the CSS class written on bound nodes.
    public var name: String
    /// CSS property → value text (e.g. "stroke": "#010101",
    /// "stroke-width": "4"). Encodes deterministically under the workfile's
    /// sorted-keys encoder.
    public var declarations: [String: String]
    public init(name: String, declarations: [String: String]) {
        self.name = name
        self.declarations = declarations
    }
}

/// Named-style engine: apply/unapply on a node, class-based binding scan,
/// and workspace propagation.
///
/// Contract (mirrors `StyleTokens`):
/// - Pure functions, no I/O; results are deterministic (document order,
///   canonical property order).
/// - Binding is BY CLASS: a node is bound to style `s` iff its `class`
///   attribute contains the token `s.name`. Foreign classes (not naming a
///   fekthor style) are always preserved.
/// - Values are always written inline in `node.style`; `classStyle` is
///   render-only and untouched (the writer never inlines it).
/// - Propagation returns ONLY documents that actually changed — the save
///   contract shared with `StyleTokens.apply`: callers never rewrite an
///   unedited file. Declarations the style does not own keep their value
///   and position; owned declarations update in place, new ones append in
///   canonical order.
public enum NamedStyles {

    /// Canonical write order for style-owned properties: known paint
    /// properties first in corpus order, then anything else alphabetically.
    /// Applying the same style twice is a no-op byte-for-byte.
    static let canonicalOrder: [String] = [
        "fill", "fill-rule", "fill-opacity",
        "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
        "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset",
        "stroke-opacity", "opacity",
    ]

    /// The paint-related properties `capture` snapshots from a node.
    static let capturedProps: Set<String> = Set(canonicalOrder)

    // MARK: - Apply / unapply

    /// Bind `style` to a node: the node's class gains `style.name`
    /// (replacing any previous fekthor style class — pass the workspace's
    /// other style names via `replacing` so a re-style swaps cleanly;
    /// unrelated classes are preserved in place) and the style's
    /// declarations are written inline in canonical order (existing
    /// declarations update in place, new ones append).
    public static func apply(
        _ style: NamedStyle, to node: ShapeNode, replacing knownStyleNames: [String] = []
    ) -> ShapeNode {
        var out = node
        var drop = Set(knownStyleNames)
        drop.insert(style.name)
        var classes = classList(of: node.attributes).filter { !drop.contains($0) }
        classes.append(style.name)
        out.attributes = settingClassList(node.attributes, to: classes)
        out.style = writing(style, into: node.style)
        return out
    }

    /// Unbind a node from style `styleName`: the class token is dropped
    /// (other classes stay) and the inline declarations keep their current
    /// values — the node looks the same, it just stops following the style.
    public static func unapply(_ node: ShapeNode, styleName: String) -> ShapeNode {
        var out = node
        let classes = classList(of: node.attributes).filter { $0 != styleName }
        out.attributes = settingClassList(node.attributes, to: classes)
        return out
    }

    /// Snapshot the node's current paint-related declarations (fill, stroke,
    /// widths, caps, joins, dash, opacity, fill-rule) as a new named style.
    /// Reads the effective style so class-resolved legacy values are
    /// captured too.
    public static func capture(from node: ShapeNode, name: String) -> NamedStyle {
        var declarations: [String: String] = [:]
        for d in node.effectiveStyle.declarations where capturedProps.contains(d.name) {
            declarations[d.name] = SVGStyle.valueText(d.value)
        }
        return NamedStyle(name: name, declarations: declarations)
    }

    // MARK: - Binding scan

    /// IDs of every node (shapes and groups, document order) whose class
    /// contains `styleName`.
    public static func boundNodes(in doc: GraphicDocument, styleName: String) -> [Int] {
        var out: [Int] = []
        walk(doc.nodes) { id, attributes in
            if classList(of: attributes).contains(styleName) { out.append(id) }
        }
        return out
    }

    // MARK: - Propagation

    /// Rewrite the inline declarations of every node bound to `style`
    /// (by class) across a workspace keyed by path. The result contains
    /// ONLY the documents that actually changed; declarations the style
    /// does not own are preserved verbatim, in place.
    public static func propagate(
        _ style: NamedStyle, docs: [String: GraphicDocument]
    ) -> [String: GraphicDocument] {
        var out: [String: GraphicDocument] = [:]
        for (key, doc) in docs {
            var changed = false
            var rewritten = doc
            rewritten.nodes = rewrite(doc.nodes, style: style, changed: &changed)
            if changed { out[key] = rewritten }
        }
        return out
    }

    // MARK: - Internals

    /// The node's class attribute as a token list (empty when absent).
    static func classList(of attributes: NodeAttributes) -> [String] {
        guard let attr = attributes.extras.first(where: { $0.name == "class" }) else {
            return []
        }
        return attr.value.split(separator: " ").map(String.init)
    }

    /// Attributes with the class attribute set to `classes` (joined with a
    /// space). An existing class attribute updates in place; a new one
    /// appends; an empty list removes the attribute entirely.
    static func settingClassList(_ attributes: NodeAttributes, to classes: [String])
        -> NodeAttributes
    {
        var out = attributes
        if classes.isEmpty {
            out.extras.removeAll { $0.name == "class" }
            return out
        }
        let value = classes.joined(separator: " ")
        if let i = out.extras.firstIndex(where: { $0.name == "class" }) {
            out.extras[i].value = value
        } else {
            out.extras.append(XMLAttr(name: "class", value: value))
        }
        return out
    }

    /// The style's properties in canonical order: known properties in
    /// `canonicalOrder` position, unknown ones appended alphabetically.
    static func orderedProperties(of style: NamedStyle) -> [String] {
        var out = canonicalOrder.filter { style.declarations[$0] != nil }
        out += style.declarations.keys
            .filter { !capturedProps.contains($0) }
            .sorted()
        return out
    }

    /// Write the style's declarations into an inline style: existing
    /// declarations update in place (`Style.set` semantics), new ones append
    /// in canonical order. Properties the style does not own are untouched.
    static func writing(_ named: NamedStyle, into style: Style) -> Style {
        var out = style
        for property in orderedProperties(of: named) {
            guard let text = named.declarations[property] else { continue }
            out.set(property, SVGStyle.value(property, text))
        }
        return out
    }

    /// Visit every node's id + attributes, groups before their children
    /// (document order).
    static func walk(_ nodes: [GraphicNode], _ visit: (Int, NodeAttributes) -> Void) {
        for node in nodes {
            switch node {
            case .raw:
                break
            case .shape(let s):
                visit(s.id, s.attributes)
            case .group(let g):
                visit(g.id, g.attributes)
                walk(g.children, visit)
            }
        }
    }

    static func rewrite(
        _ nodes: [GraphicNode], style: NamedStyle, changed: inout Bool
    ) -> [GraphicNode] {
        nodes.map { node in
            switch node {
            case .raw:
                return node
            case .shape(var s):
                if classList(of: s.attributes).contains(style.name) {
                    let rewritten = writing(style, into: s.style)
                    if rewritten != s.style {
                        s.style = rewritten
                        changed = true
                    }
                }
                return .shape(s)
            case .group(var g):
                if classList(of: g.attributes).contains(style.name) {
                    let rewritten = writing(style, into: g.style)
                    if rewritten != g.style {
                        g.style = rewritten
                        changed = true
                    }
                }
                g.children = rewrite(g.children, style: style, changed: &changed)
                return .group(g)
            }
        }
    }
}
