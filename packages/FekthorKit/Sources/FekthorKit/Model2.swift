import Foundation

// MARK: - Document Model v2 (editor)
//
// The editor's scene model. The trace model (`VectorDocument`) stays as the
// tracing pipeline's output; `Model2Bridge` maps it into this model one-way.
//
// Design rules (see docs/fekthor/EDITOR-PLAN.md):
// - A shape carries fill AND stroke together (the trace model's fill-XOR-
//   stroke split is the flaw this model fixes).
// - Style is an ORDERED declaration list mirroring the SVG `style=""`
//   attribute — unknown properties round-trip verbatim, and an untouched
//   node serializes back exactly as it was read.
// - Primitives stay primitives (`<rect>` stays a rect) until edited.
// - Node ids are deterministic sequential Ints assigned in document order,
//   so two reads of the same file produce EQUAL documents (round-trip tests
//   rely on this); they are never serialized.

/// The SVG viewBox rectangle.
public struct ViewBox: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var width: Double
    public var height: Double
    public init(minX: Double = 0, minY: Double = 0, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }
}

/// One XML attribute, order-preserving.
public struct XMLAttr: Equatable, Sendable {
    public var name: String
    public var value: String
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// A parsed `transform` attribute: the raw string is preserved for verbatim
/// write-back; the matrix (a b c d tx ty, SVG order) is used for rendering
/// and is baked into geometry on the first geometry edit.
public struct TransformValue: Equatable, Sendable {
    public var raw: String
    public var matrix: [Double]  // [a, b, c, d, tx, ty]
    public init(raw: String, matrix: [Double]) {
        self.raw = raw
        self.matrix = matrix
    }

    public static let identity = TransformValue(raw: "", matrix: [1, 0, 0, 1, 0, 0])

    public func apply(_ p: Pt) -> Pt {
        Pt(
            matrix[0] * p.x + matrix[2] * p.y + matrix[4],
            matrix[1] * p.x + matrix[3] * p.y + matrix[5])
    }
}

// MARK: Style

/// A paint value as SVG expresses it. `raw` preserves anything we do not
/// model (currentColor, var(--x, fallback), …) verbatim.
public enum PaintValue: Equatable, Sendable {
    case color(r: UInt8, g: UInt8, b: UInt8)
    case none
    case linear(LinearGradient)
    case radial(RadialGradient)
    case reference(String)  // url(#id)
    case raw(String)

    /// A best-effort concrete colour for rendering. `var(--x, #hex)` falls
    /// back to its fallback; `currentColor` and unresolvable values render
    /// black (matching browser default text colour behaviour on icons).
    public var renderColor: (r: UInt8, g: UInt8, b: UInt8)? {
        switch self {
        case .color(let r, let g, let b): return (r, g, b)
        case .none: return nil
        case .linear(let g):
            let c = g.stops.first?.color ?? [0, 0, 0]
            return (c.count > 2 ? (c[0], c[1], c[2]) : (0, 0, 0))
        case .radial(let g):
            let c = g.stops.first?.color ?? [0, 0, 0]
            return (c.count > 2 ? (c[0], c[1], c[2]) : (0, 0, 0))
        case .reference: return (0, 0, 0)
        case .raw(let s):
            // var(--name, fallback) → try the fallback; else black.
            if let open = s.range(of: ","), s.hasPrefix("var("), s.hasSuffix(")") {
                let fallback = String(s[open.upperBound..<s.index(before: s.endIndex)])
                    .trimmingCharacters(in: .whitespaces)
                if let c = PaintValue.parseHex(fallback) { return c }
            }
            return (0, 0, 0)
        }
    }

    /// Parse #rgb / #rrggbb (lowercase or uppercase).
    public static func parseHex(_ s: String) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard s.hasPrefix("#") else { return nil }
        let hex = String(s.dropFirst())
        func val(_ sub: Substring) -> UInt8? { UInt8(sub, radix: 16) }
        if hex.count == 3 {
            let chars = Array(hex)
            guard let r = val(Substring(String([chars[0], chars[0]]))),
                let g = val(Substring(String([chars[1], chars[1]]))),
                let b = val(Substring(String([chars[2], chars[2]])))
            else { return nil }
            return (r, g, b)
        }
        if hex.count == 6 {
            let a = hex.startIndex
            let b1 = hex.index(a, offsetBy: 2)
            let c1 = hex.index(a, offsetBy: 4)
            guard let r = val(hex[a..<b1]), let g = val(hex[b1..<c1]),
                let b = val(hex[c1...])
            else { return nil }
            return (r, g, b)
        }
        return nil
    }
}

/// A typed CSS declaration value. `.raw` is the verbatim fallback that keeps
/// unknown values round-trip safe.
public enum StyleValue: Equatable, Sendable {
    case paint(PaintValue)
    case number(Double, unit: String?)
    case keyword(String)
    case raw(String)
}

public struct StyleDeclaration: Equatable, Sendable {
    public var name: String
    public var value: StyleValue
    public init(name: String, value: StyleValue) {
        self.name = name
        self.value = value
    }
}

/// An ordered inline style. Order is preserved on write; setting an existing
/// property updates it in place, new properties append.
public struct Style: Equatable, Sendable {
    public var declarations: [StyleDeclaration]
    public init(declarations: [StyleDeclaration] = []) {
        self.declarations = declarations
    }

    public func value(of name: String) -> StyleValue? {
        declarations.last(where: { $0.name == name })?.value
    }

    public mutating func set(_ name: String, _ value: StyleValue) {
        if let i = declarations.lastIndex(where: { $0.name == name }) {
            declarations[i].value = value
        } else {
            declarations.append(StyleDeclaration(name: name, value: value))
        }
    }

    public mutating func remove(_ name: String) {
        declarations.removeAll { $0.name == name }
    }

    // Typed conveniences.
    public var fill: PaintValue? {
        get { if case .paint(let p)? = value(of: "fill") { return p } else { return nil } }
        set {
            if let newValue { set("fill", .paint(newValue)) } else { remove("fill") }
        }
    }
    public var stroke: PaintValue? {
        get { if case .paint(let p)? = value(of: "stroke") { return p } else { return nil } }
        set {
            if let newValue { set("stroke", .paint(newValue)) } else { remove("stroke") }
        }
    }
    public var strokeWidth: Double? {
        get {
            if case .number(let n, _)? = value(of: "stroke-width") { return n } else { return nil }
        }
        set {
            if let newValue {
                // Preserve an existing unit (corpus uses `4px`).
                var unit: String? = nil
                if case .number(_, let u)? = value(of: "stroke-width") { unit = u }
                set("stroke-width", .number(newValue, unit: unit))
            } else {
                remove("stroke-width")
            }
        }
    }
    public var opacity: Double? {
        get { if case .number(let n, _)? = value(of: "opacity") { return n } else { return nil } }
        set {
            if let newValue { set("opacity", .number(newValue, unit: nil)) } else {
                remove("opacity")
            }
        }
    }
}

// MARK: Nodes

/// Non-style attributes carried by a node: the SVG `id` plus any extra
/// attributes (class, data-name, …) in source order.
public struct NodeAttributes: Equatable, Sendable {
    public var svgID: String?
    public var extras: [XMLAttr]
    public init(svgID: String? = nil, extras: [XMLAttr] = []) {
        self.svgID = svgID
        self.extras = extras
    }
}

/// Shape geometry in its source form. Primitives are preserved as primitives
/// until an anchor-level edit expands them to `.path`.
public enum ShapeKind: Equatable, Sendable {
    case path([RefinedPath])
    case line(Pt, Pt)
    case polyline([Pt])
    case polygon([Pt])
    case rect(x: Double, y: Double, width: Double, height: Double, rx: Double?, ry: Double?)
    case circle(center: Pt, r: Double)
    case ellipse(center: Pt, rx: Double, ry: Double)
}

public struct ShapeNode: Equatable, Sendable {
    /// Deterministic in-document id (selection/undo); never serialized.
    public var id: Int
    public var kind: ShapeKind
    public var style: Style
    public var attributes: NodeAttributes
    public var transform: TransformValue?
    /// Style resolved from a document `<style>` block via the node's class
    /// (rare legacy Illustrator exports). Render-only: the writer never
    /// inlines it — the class attribute and the style block are preserved,
    /// and `style` only gains declarations when the user edits the node.
    public var classStyle: Style?
    public init(
        id: Int, kind: ShapeKind, style: Style = Style(),
        attributes: NodeAttributes = NodeAttributes(), transform: TransformValue? = nil,
        classStyle: Style? = nil
    ) {
        self.id = id
        self.kind = kind
        self.style = style
        self.attributes = attributes
        self.transform = transform
        self.classStyle = classStyle
    }

    /// Effective style for rendering: class-resolved declarations first,
    /// inline declarations override (CSS cascade: inline wins).
    public var effectiveStyle: Style {
        guard let classStyle else { return style }
        var merged = classStyle
        for d in style.declarations { merged.set(d.name, d.value) }
        return merged
    }
}

public struct GroupNode: Equatable, Sendable {
    public var id: Int
    public var style: Style
    public var attributes: NodeAttributes
    public var transform: TransformValue?
    public var children: [GraphicNode]
    public init(
        id: Int, style: Style = Style(), attributes: NodeAttributes = NodeAttributes(),
        transform: TransformValue? = nil, children: [GraphicNode] = []
    ) {
        self.id = id
        self.style = style
        self.attributes = attributes
        self.transform = transform
        self.children = children
    }
}

/// Opaque passthrough for constructs we preserve but do not edit
/// (defs, style blocks, clipPath, unknown elements). Stored as the exact
/// serialized XML fragment.
public struct RawNode: Equatable, Sendable {
    public var id: Int
    public var xml: String
    public init(id: Int, xml: String) {
        self.id = id
        self.xml = xml
    }
}

public indirect enum GraphicNode: Equatable, Sendable {
    case shape(ShapeNode)
    case group(GroupNode)
    /// A placed raster (`<image>`), see `ImageNode`.
    case image(ImageNode)
    case raw(RawNode)

    public var id: Int {
        switch self {
        case .shape(let s): return s.id
        case .group(let g): return g.id
        case .image(let i): return i.id
        case .raw(let r): return r.id
        }
    }
}

// MARK: Document

public struct GraphicDocument: Equatable, Sendable {
    public var viewBox: ViewBox
    /// Root <svg> attributes in source order, EXCLUDING viewBox (typed above).
    public var rootAttributes: [XMLAttr]
    public var hadXMLDeclaration: Bool
    public var nodes: [GraphicNode]

    public init(
        viewBox: ViewBox, rootAttributes: [XMLAttr] = [], hadXMLDeclaration: Bool = false,
        nodes: [GraphicNode] = []
    ) {
        self.viewBox = viewBox
        self.rootAttributes = rootAttributes
        self.hadXMLDeclaration = hadXMLDeclaration
        self.nodes = nodes
    }

    /// A fresh blank document (new-file flow): canonical root attributes.
    public static func blank(width: Double, height: Double, id: String? = nil) -> GraphicDocument {
        var attrs: [XMLAttr] = []
        if let id { attrs.append(XMLAttr(name: "id", value: id)) }
        attrs.append(XMLAttr(name: "xmlns", value: "http://www.w3.org/2000/svg"))
        return GraphicDocument(
            viewBox: ViewBox(width: width, height: height), rootAttributes: attrs,
            hadXMLDeclaration: false, nodes: [])
    }

    /// The next free node id (nodes may nest inside groups).
    public var nextNodeID: Int {
        var maxID = -1
        func walk(_ nodes: [GraphicNode]) {
            for n in nodes {
                maxID = Swift.max(maxID, n.id)
                if case .group(let g) = n { walk(g.children) }
            }
        }
        walk(nodes)
        return maxID + 1
    }

    /// Find a node (depth-first) and its keypath-ish location.
    public func firstShape(id: Int) -> ShapeNode? {
        func walk(_ nodes: [GraphicNode]) -> ShapeNode? {
            for n in nodes {
                switch n {
                case .shape(let s) where s.id == id: return s
                case .group(let g):
                    if let hit = walk(g.children) { return hit }
                default: break
                }
            }
            return nil
        }
        return walk(nodes)
    }

    /// Replace a shape by id anywhere in the tree. Returns false if absent.
    @discardableResult
    public mutating func replaceShape(id: Int, with shape: ShapeNode) -> Bool {
        func walk(_ nodes: inout [GraphicNode]) -> Bool {
            for i in nodes.indices {
                switch nodes[i] {
                case .shape(let s) where s.id == id:
                    nodes[i] = .shape(shape)
                    return true
                case .group(var g):
                    if walk(&g.children) {
                        nodes[i] = .group(g)
                        return true
                    }
                default: break
                }
            }
            return false
        }
        return walk(&nodes)
    }

    /// Find a placed image by id (depth-first).
    public func firstImage(id: Int) -> ImageNode? {
        func walk(_ nodes: [GraphicNode]) -> ImageNode? {
            for n in nodes {
                switch n {
                case .image(let i) where i.id == id: return i
                case .group(let g):
                    if let hit = walk(g.children) { return hit }
                default: break
                }
            }
            return nil
        }
        return walk(nodes)
    }

    /// Replace an image by id anywhere in the tree. Returns false if absent.
    @discardableResult
    public mutating func replaceImage(id: Int, with image: ImageNode) -> Bool {
        replaceNode(id: id, with: [.image(image)])
    }

    /// Replace any node by id with zero or more nodes, in place (z-order is
    /// preserved: the replacements sit exactly where the original was). This
    /// is what Vectorize uses to swap an image for the traced geometry.
    @discardableResult
    public mutating func replaceNode(id: Int, with replacements: [GraphicNode]) -> Bool {
        func walk(_ nodes: inout [GraphicNode]) -> Bool {
            for i in nodes.indices {
                if nodes[i].id == id {
                    nodes.replaceSubrange(i...i, with: replacements)
                    return true
                }
                if case .group(var g) = nodes[i] {
                    if walk(&g.children) {
                        nodes[i] = .group(g)
                        return true
                    }
                }
            }
            return false
        }
        return walk(&nodes)
    }
}

// MARK: Equatable conformances for reused trace types

extension GradientStop: Equatable {
    public static func == (lhs: GradientStop, rhs: GradientStop) -> Bool {
        lhs.color == rhs.color && lhs.offset == rhs.offset
    }
}
extension LinearGradient: Equatable {
    public static func == (lhs: LinearGradient, rhs: LinearGradient) -> Bool {
        lhs.p0 == rhs.p0 && lhs.p1 == rhs.p1 && lhs.stops == rhs.stops
    }
}
extension RadialGradient: Equatable {
    public static func == (lhs: RadialGradient, rhs: RadialGradient) -> Bool {
        lhs.center == rhs.center && lhs.radius == rhs.radius && lhs.stops == rhs.stops
    }
}
