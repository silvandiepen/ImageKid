import Foundation

/// Workspace-level named style tokens (P3).
///
/// A token is a named colour slot (`outline = #010101`, `accent = #ed2024`).
/// Tokens bind to shapes by COLOUR-SLOT MATCHING, not by node ids: every
/// style declaration whose value is exactly the token's colour is bound to
/// it, wherever it appears in the tree. Changing a token's value rewrites
/// every bound paint; everything else round-trips verbatim.
///
/// Contract:
/// - Pure functions, no I/O; results are deterministic (document order).
/// - Matching is exact RGB equality after normalization — `#010102` never
///   binds to `#010101`.
/// - Only inline styles are scanned/rewritten; `classStyle` is render-only
///   (the writer never inlines it) and is left untouched.
/// - Propagation returns ONLY documents that actually changed, so callers
///   never rewrite an unedited file. Untouched declarations are preserved
///   verbatim, and edited declarations keep their position in the list.
public enum StyleTokens {

    // MARK: Colour normalization

    /// A normalized RGB triple used for slot matching.
    public struct RGB: Equatable, Hashable, Sendable {
        public var r: UInt8
        public var g: UInt8
        public var b: UInt8
        public init(r: UInt8, g: UInt8, b: UInt8) {
            self.r = r
            self.g = g
            self.b = b
        }

        /// Corpus-style hex text: lowercase `#rrggbb`, shorthand (`#333`)
        /// when every channel has doubled digits — matches the writer.
        public var hexText: String {
            SVGStyle.paintText(.color(r: r, g: g, b: b))
        }
    }

    /// Parse a colour string to RGB for matching: `#rgb` / `#rrggbb`
    /// (either case) or `rgb(r, g, b)` with 0–255 integer components.
    /// Anything else (`none`, keywords, gradients, out-of-range) is nil.
    public static func normalizeColor(_ text: String) -> RGB? {
        let s = text.trimmingCharacters(in: .whitespaces)
        if let c = PaintValue.parseHex(s) {
            return RGB(r: c.r, g: c.g, b: c.b)
        }
        guard s.lowercased().hasPrefix("rgb("), s.hasSuffix(")") else { return nil }
        let parts = s.dropFirst(4).dropLast().split(separator: ",")
        guard parts.count == 3 else { return nil }
        var channels: [UInt8] = []
        for part in parts {
            guard let v = Int(part.trimmingCharacters(in: .whitespaces)),
                (0...255).contains(v)
            else { return nil }
            channels.append(UInt8(v))
        }
        return RGB(r: channels[0], g: channels[1], b: channels[2])
    }

    // MARK: Binding scan

    /// One matched colour slot: node `nodeID`'s declaration `property`
    /// (fill, stroke, or any other declaration whose value is a colour)
    /// carries the colour of token `token`.
    public struct Binding: Equatable, Sendable {
        public var nodeID: Int
        public var property: String
        public var token: String
        public init(nodeID: Int, property: String, token: String) {
            self.nodeID = nodeID
            self.property = property
            self.token = token
        }
    }

    /// Scan a document (groups walked recursively, document order) for every
    /// declaration whose colour equals a token's colour. When two tokens
    /// share a colour, the first in `tokens` wins.
    public static func bindings(
        in doc: GraphicDocument, tokens: [Workfile.StyleToken]
    ) -> [Binding] {
        let table = resolved(tokens)
        var out: [Binding] = []
        walkStyles(doc.nodes) { nodeID, style in
            for declaration in style.declarations {
                guard let rgb = colorValue(declaration.value),
                    let hit = table.first(where: { $0.rgb == rgb })
                else { continue }
                out.append(Binding(nodeID: nodeID, property: declaration.name, token: hit.name))
            }
        }
        return out
    }

    /// Colours present in the document that match NO token, in order of
    /// first appearance (the UI offers "create token from this" for each).
    public static func unboundColors(
        in doc: GraphicDocument, tokens: [Workfile.StyleToken]
    ) -> [RGB] {
        let bound = Set(resolved(tokens).map(\.rgb))
        var seen = Set<RGB>()
        var out: [RGB] = []
        walkStyles(doc.nodes) { _, style in
            for declaration in style.declarations {
                guard let rgb = colorValue(declaration.value),
                    !bound.contains(rgb), seen.insert(rgb).inserted
                else { continue }
                out.append(rgb)
            }
        }
        return out
    }

    // MARK: Propagation

    /// Rewrite every paint bound to token `name` from its current colour to
    /// `newValue`. Returns nil when nothing changed (unknown token,
    /// unparseable value, same colour, or no bound paint in the document) —
    /// the save contract: only edited documents are ever rewritten.
    public static func apply(
        tokens: [Workfile.StyleToken], changing name: String, to newValue: String,
        doc: GraphicDocument
    ) -> GraphicDocument? {
        guard let token = tokens.first(where: { $0.name == name }),
            let old = normalizeColor(token.value),
            let new = normalizeColor(newValue),
            old != new
        else { return nil }
        var changed = false
        var out = doc
        out.nodes = rewrite(doc.nodes, from: old, to: new, changed: &changed)
        return changed ? out : nil
    }

    /// Multi-document propagation over a workspace keyed by path. The result
    /// contains ONLY the documents that actually changed.
    public static func apply(
        tokens: [Workfile.StyleToken], changing name: String, to newValue: String,
        docs: [String: GraphicDocument]
    ) -> [String: GraphicDocument] {
        var out: [String: GraphicDocument] = [:]
        for (key, doc) in docs {
            if let rewritten = apply(tokens: tokens, changing: name, to: newValue, doc: doc) {
                out[key] = rewritten
            }
        }
        return out
    }

    // MARK: Draw-with-style

    /// Build a Style from token references for drawing new shapes:
    /// `["stroke": "outline"]` → `stroke: #010101`. Starts from `base` when
    /// given (existing declarations update in place, new ones append —
    /// `Style.set` semantics). Properties are applied in sorted order so the
    /// appended tail is deterministic; unknown token names are skipped.
    public static func style(
        for tokenNames: [String: String], tokens: [Workfile.StyleToken], base: Style? = nil
    ) -> Style {
        var out = base ?? Style()
        for property in tokenNames.keys.sorted() {
            guard let tokenName = tokenNames[property],
                let token = tokens.first(where: { $0.name == tokenName }),
                let rgb = normalizeColor(token.value)
            else { continue }
            if property == "fill" || property == "stroke" {
                out.set(property, .paint(.color(r: rgb.r, g: rgb.g, b: rgb.b)))
            } else {
                out.set(property, .raw(rgb.hexText))
            }
        }
        return out
    }

    // MARK: Internals

    /// Tokens whose value parses to a colour, in declaration order.
    static func resolved(_ tokens: [Workfile.StyleToken]) -> [(name: String, rgb: RGB)] {
        tokens.compactMap { token in
            normalizeColor(token.value).map { (token.name, $0) }
        }
    }

    /// The RGB a declaration value carries, if any: typed colour paints,
    /// raw paint text (`rgb(1,1,1)`), and raw non-paint declarations whose
    /// value parses to a colour (`stop-color: #010101`).
    static func colorValue(_ value: StyleValue) -> RGB? {
        switch value {
        case .paint(.color(let r, let g, let b)): return RGB(r: r, g: g, b: b)
        case .paint(.raw(let s)): return normalizeColor(s)
        case .raw(let s): return normalizeColor(s)
        default: return nil
        }
    }

    /// Visit every node's inline style, groups before their children
    /// (document order).
    static func walkStyles(_ nodes: [GraphicNode], _ visit: (Int, Style) -> Void) {
        for node in nodes {
            switch node {
            // Placed rasters carry no paint: colour slots skip them.
            case .raw, .image:
                break
            case .shape(let s):
                visit(s.id, s.style)
            case .group(let g):
                visit(g.id, g.style)
                walkStyles(g.children, visit)
            }
        }
    }

    static func rewrite(
        _ nodes: [GraphicNode], from old: RGB, to new: RGB, changed: inout Bool
    ) -> [GraphicNode] {
        nodes.map { node in
            switch node {
            case .raw, .image:
                return node
            case .shape(var s):
                s.style = rewriteStyle(s.style, from: old, to: new, changed: &changed)
                return .shape(s)
            case .group(var g):
                g.style = rewriteStyle(g.style, from: old, to: new, changed: &changed)
                g.children = rewrite(g.children, from: old, to: new, changed: &changed)
                return .group(g)
            }
        }
    }

    /// Rewrite matching declarations in place: order is preserved, matched
    /// values become the new colour (paints as typed colours, raw
    /// declarations as corpus-formatted hex), everything else is untouched.
    static func rewriteStyle(
        _ style: Style, from old: RGB, to new: RGB, changed: inout Bool
    ) -> Style {
        var out = style
        for i in out.declarations.indices {
            guard colorValue(out.declarations[i].value) == old else { continue }
            switch out.declarations[i].value {
            case .paint:
                out.declarations[i].value = .paint(.color(r: new.r, g: new.g, b: new.b))
            case .raw:
                out.declarations[i].value = .raw(new.hexText)
            default:
                continue
            }
            changed = true
        }
        return out
    }
}
