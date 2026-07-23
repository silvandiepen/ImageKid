import Foundation

// MARK: - Export actions (P2 export-profile engine)
//
// A `Workfile.ExportProfile` stores its pipeline as opaque strings (the
// schema stays `[String]` so old builds skip what they don't know). This file
// gives those strings a typed grammar and a non-destructive implementation:
// every action maps `GraphicDocument → GraphicDocument`, the input document
// is never mutated, and running the same profile twice yields byte-identical
// SVG output (determinism contract, docs/fekthor/EDITOR-PLAN.md).

/// Typed parse failure for an export-profile action string. Parsing is
/// forgiving about whitespace, case of the action name, and aliases; anything
/// unrecognisable is reported as one of these, never silently dropped.
public enum ExportActionError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The action name is not in the grammar (e.g. "smooth-magic").
    case unknownAction(String)
    /// The action name is known but its payload is not usable.
    case malformedAction(action: String, reason: String)

    public var description: String {
        switch self {
        case .unknownAction(let name):
            return "unknown export action \"\(name)\""
        case .malformedAction(let action, let reason):
            return "malformed export action \"\(action)\": \(reason)"
        }
    }
}

/// One step of an export pipeline, parsed from the opaque strings stored in
/// `Workfile.ExportProfile.actions`.
///
/// Grammar — an action is `name` or `name:payload` (first `:` splits; the
/// payload may itself contain `:` and `=`). Names are case-insensitive and
/// surrounding whitespace is ignored.
///
/// ```
/// outline-strokes                       stroke → fill expansion (alias: outline)
/// flatten                               bake transforms, expand primitives to
///                                       paths, dissolve groups into the parent
/// strip-ids                             drop id / data-name from every node
///                                       (root <svg> attributes kept; alias: strip)
/// resize:<W>x<H>   resize:<S>           uniform scale into a W×H (or S×S)
///                                       viewBox, centered (alias: fit)
/// recolor:[fill:|stroke:]<from>=<to>    rewrite paints matching <from>:
///     <from>  #hex (#rgb/#rrggbb), none, or verbatim text (currentColor,
///             var(--x, #fff), …) — matched against fill/stroke declarations;
///             the optional scope prefix restricts to one property.
///     <to>    #hex, none, currentColor, var(--name, fallback) — written
///             verbatim so output text matches the target corpus exactly —
///             or the keyword `remove` to delete the declaration.
/// stroke-width:<n>[unit]                set stroke-width declarations to n
///                                       (existing unit preserved unless one
///                                       is given)
/// stroke-width:x<f>                     scale numeric stroke-widths by f
///                                       (also *<f>)
/// stroke-width:<n>[unit]=<value>        map declarations whose width equals n
///                                       (and unit, when given) to a verbatim
///                                       value, e.g. 4px=var(--w, 5)
/// restyle:<prop>:<match>=<value>        rewrite existing declarations of
///                                       <prop> whose serialized value equals
///                                       <match> (`*` = any) to the verbatim
///                                       <value>; empty <value> deletes the
///                                       declaration. Never adds new ones.
/// ```
///
/// Example — the open-icon library build, encoded as a profile:
/// ```
/// recolor:stroke:#231f20=remove
/// recolor:fill:#ed2024=var(--icon-fill, rgba(0, 0, 0, 0))
/// restyle:opacity:.5=var(--icon-fill-opacity, 1)
/// stroke-width:4px=var(--icon-stroke-width-m, calc(var(--icon-stroke-width, 5) * 1))
/// ```
public enum ExportAction: Equatable, Sendable {
    /// Which paint properties a recolor touches.
    public enum PaintScope: Equatable, Sendable {
        case fill
        case stroke
        case both
    }

    /// What a matched paint becomes: a verbatim value, or removal.
    public enum PaintTarget: Equatable, Sendable {
        case paint(String)
        case remove
    }

    /// Set / scale / map for stroke-width declarations.
    public enum StrokeWidthOp: Equatable, Sendable {
        case set(value: Double, unit: String?)
        case scale(Double)
        case map(value: Double, unit: String?, to: String)
    }

    case outlineStrokes
    case flatten
    case stripIDs
    case resize(width: Double, height: Double)
    case recolor(scope: PaintScope, from: String, to: PaintTarget)
    case strokeWidth(StrokeWidthOp)
    case restyle(property: String, match: String?, value: String?)

    // MARK: Parsing

    /// Parse one opaque action string. Throws `ExportActionError`.
    public static func parse(_ raw: String) throws -> ExportAction {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExportActionError.malformedAction(action: raw, reason: "empty action")
        }
        let name: String
        let payload: String?
        if let colon = trimmed.firstIndex(of: ":") {
            name = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            payload = String(trimmed[trimmed.index(after: colon)...])
        } else {
            name = trimmed.lowercased()
            payload = nil
        }

        func noPayload() throws {
            if let payload, !payload.trimmingCharacters(in: .whitespaces).isEmpty {
                throw ExportActionError.malformedAction(
                    action: trimmed, reason: "takes no payload")
            }
        }
        func requirePayload() throws -> String {
            guard let payload, !payload.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ExportActionError.malformedAction(
                    action: trimmed, reason: "missing payload")
            }
            return payload
        }

        switch name {
        case "outline-strokes", "outline":
            try noPayload()
            return .outlineStrokes
        case "flatten":
            try noPayload()
            return .flatten
        case "strip-ids", "strip":
            try noPayload()
            return .stripIDs
        case "resize", "fit":
            let p = try requirePayload().trimmingCharacters(in: .whitespaces).lowercased()
            let parts = p.split(separator: "x", maxSplits: 1)
            let w = Double(parts[0].trimmingCharacters(in: .whitespaces))
            let h = parts.count > 1
                ? Double(parts[1].trimmingCharacters(in: .whitespaces)) : w
            guard let w, let h, w > 0, h > 0 else {
                throw ExportActionError.malformedAction(
                    action: trimmed, reason: "expected <W>x<H> or <S>, got \"\(p)\"")
            }
            return .resize(width: w, height: h)
        case "recolor":
            let p = try requirePayload()
            guard let eq = p.firstIndex(of: "=") else {
                throw ExportActionError.malformedAction(
                    action: trimmed, reason: "expected <from>=<to>")
            }
            var from = String(p[..<eq]).trimmingCharacters(in: .whitespaces)
            let to = String(p[p.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            var scope = PaintScope.both
            let lowered = from.lowercased()
            if lowered.hasPrefix("fill:") {
                scope = .fill
                from = String(from.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if lowered.hasPrefix("stroke:") {
                scope = .stroke
                from = String(from.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            guard !from.isEmpty, !to.isEmpty else {
                throw ExportActionError.malformedAction(
                    action: trimmed, reason: "empty source or target paint")
            }
            let target: PaintTarget = to.lowercased() == "remove" ? .remove : .paint(to)
            return .recolor(scope: scope, from: from, to: target)
        case "stroke-width":
            let p = try requirePayload()
            if let eq = p.firstIndex(of: "=") {
                let lhs = String(p[..<eq]).trimmingCharacters(in: .whitespaces)
                let rhs = String(p[p.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                guard let (value, unit) = splitNumberUnit(lhs), !rhs.isEmpty else {
                    throw ExportActionError.malformedAction(
                        action: trimmed, reason: "expected <n>[unit]=<value>")
                }
                return .strokeWidth(.map(value: value, unit: unit, to: rhs))
            }
            let body = p.trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("x") || body.hasPrefix("*") {
                guard let f = Double(body.dropFirst()), f > 0 else {
                    throw ExportActionError.malformedAction(
                        action: trimmed, reason: "expected x<factor>")
                }
                return .strokeWidth(.scale(f))
            }
            guard let (value, unit) = splitNumberUnit(body), value >= 0 else {
                throw ExportActionError.malformedAction(
                    action: trimmed, reason: "expected <n>[unit], x<factor> or <n>=<value>")
            }
            return .strokeWidth(.set(value: value, unit: unit))
        case "restyle":
            let p = try requirePayload()
            guard let colon = p.firstIndex(of: ":") else {
                throw ExportActionError.malformedAction(
                    action: trimmed, reason: "expected <prop>:<match>=<value>")
            }
            let prop = String(p[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(p[p.index(after: colon)...])
            guard !prop.isEmpty, let eq = rest.firstIndex(of: "=") else {
                throw ExportActionError.malformedAction(
                    action: trimmed, reason: "expected <prop>:<match>=<value>")
            }
            let match = String(rest[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(rest[rest.index(after: eq)...])
                .trimmingCharacters(in: .whitespaces)
            guard !match.isEmpty else {
                throw ExportActionError.malformedAction(
                    action: trimmed, reason: "empty match (use * for any)")
            }
            return .restyle(
                property: prop, match: match == "*" ? nil : match,
                value: value.isEmpty ? nil : value)
        default:
            throw ExportActionError.unknownAction(name)
        }
    }

    /// "4px" → (4, "px"); "2" → (2, nil). Unit must be letters or %.
    static func splitNumberUnit(_ text: String) -> (Double, String?)? {
        var digits = ""
        var unit = ""
        var inUnit = false
        for ch in text {
            if !inUnit, ch.isNumber || ch == "." || ch == "-" || ch == "+" || ch == "e" {
                digits.append(ch)
            } else {
                inUnit = true
                unit.append(ch)
            }
        }
        guard let n = Double(digits), unit.allSatisfy({ $0.isLetter || $0 == "%" }) else {
            return nil
        }
        return (n, unit.isEmpty ? nil : unit)
    }

    // MARK: Application

    /// Apply this action. Non-destructive: returns a new document.
    public func applied(to doc: GraphicDocument) -> GraphicDocument {
        switch self {
        case .outlineStrokes:
            return ExportApply.outlineStrokes(doc)
        case .flatten:
            return ExportApply.flatten(doc)
        case .stripIDs:
            return ExportApply.stripIDs(doc)
        case .resize(let w, let h):
            return ExportApply.resize(doc, width: w, height: h)
        case .recolor(let scope, let from, let to):
            return ExportApply.recolor(doc, scope: scope, from: from, to: to)
        case .strokeWidth(let op):
            return ExportApply.strokeWidth(doc, op: op)
        case .restyle(let property, let match, let value):
            return ExportApply.restyle(doc, property: property, match: match, value: value)
        }
    }
}

// MARK: - Action implementations

/// The document transforms behind `ExportAction`. Kept separate so the enum
/// stays a small parseable value type.
enum ExportApply {
    // MARK: Style walking

    /// Apply `edit` to every shape and group style in the tree, in order.
    static func mapStyles(_ doc: GraphicDocument, _ edit: (inout Style) -> Void)
        -> GraphicDocument
    {
        var out = doc
        func walk(_ nodes: inout [GraphicNode]) {
            for i in nodes.indices {
                switch nodes[i] {
                case .shape(var s):
                    edit(&s.style)
                    nodes[i] = .shape(s)
                case .group(var g):
                    edit(&g.style)
                    walk(&g.children)
                    nodes[i] = .group(g)
                case .raw:
                    break
                }
            }
        }
        walk(&out.nodes)
        return out
    }

    /// Lowercased, whitespace-collapsed text for verbatim paint comparison.
    static func normalized(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .joined(separator: " ")
    }

    // MARK: recolor

    static func paintMatches(_ paint: PaintValue, from: String) -> Bool {
        let norm = normalized(from)
        if norm == "none" {
            if case PaintValue.none = paint { return true }
            return false
        }
        if let hex = PaintValue.parseHex(norm) {
            if case .color(let r, let g, let b) = paint {
                return (r, g, b) == hex
            }
            if case .raw(let s) = paint, let other = PaintValue.parseHex(normalized(s)) {
                return other == hex
            }
            return false
        }
        if case .raw(let s) = paint { return normalized(s) == norm }
        return false
    }

    /// The replacement paint. A hex whose canonical serialization equals the
    /// given text becomes a typed `.color` (renderable); everything else is
    /// preserved verbatim as `.raw` so output text matches the target corpus.
    static func targetPaint(_ text: String) -> PaintValue {
        if text == "none" { return PaintValue.none }
        if let hex = PaintValue.parseHex(text) {
            let typed = PaintValue.color(r: hex.r, g: hex.g, b: hex.b)
            if SVGStyle.paintText(typed) == text { return typed }
        }
        return .raw(text)
    }

    static func recolor(
        _ doc: GraphicDocument, scope: ExportAction.PaintScope, from: String,
        to: ExportAction.PaintTarget
    ) -> GraphicDocument {
        let names: [String]
        switch scope {
        case .fill: names = ["fill"]
        case .stroke: names = ["stroke"]
        case .both: names = ["fill", "stroke"]
        }
        return mapStyles(doc) { style in
            var kept: [StyleDeclaration] = []
            kept.reserveCapacity(style.declarations.count)
            for var d in style.declarations {
                if names.contains(d.name), case .paint(let p) = d.value,
                    paintMatches(p, from: from)
                {
                    switch to {
                    case .remove:
                        continue
                    case .paint(let text):
                        d.value = .paint(targetPaint(text))
                    }
                }
                kept.append(d)
            }
            style.declarations = kept
        }
    }

    // MARK: stroke-width

    static func strokeWidth(_ doc: GraphicDocument, op: ExportAction.StrokeWidthOp)
        -> GraphicDocument
    {
        mapStyles(doc) { style in
            for i in style.declarations.indices
            where style.declarations[i].name == "stroke-width" {
                switch op {
                case .set(let value, let unit):
                    var kept: String? = unit
                    if kept == nil, case .number(_, let u) = style.declarations[i].value {
                        kept = u
                    }
                    style.declarations[i].value = .number(value, unit: kept)
                case .scale(let f):
                    if case .number(let n, let u) = style.declarations[i].value {
                        style.declarations[i].value = .number(n * f, unit: u)
                    }
                case .map(let value, let unit, let to):
                    if case .number(let n, let u) = style.declarations[i].value,
                        n == value, unit == nil || unit == u
                    {
                        style.declarations[i].value = .raw(to)
                    }
                }
            }
        }
    }

    // MARK: restyle

    static func restyle(
        _ doc: GraphicDocument, property: String, match: String?, value: String?
    ) -> GraphicDocument {
        mapStyles(doc) { style in
            var kept: [StyleDeclaration] = []
            kept.reserveCapacity(style.declarations.count)
            for var d in style.declarations {
                if d.name == property,
                    match == nil || SVGStyle.valueText(d.value) == match
                {
                    guard let value else { continue }
                    d.value = .raw(value)
                }
                kept.append(d)
            }
            style.declarations = kept
        }
    }

    // MARK: strip-ids

    static func stripIDs(_ doc: GraphicDocument) -> GraphicDocument {
        var out = doc
        func walk(_ nodes: inout [GraphicNode]) {
            for i in nodes.indices {
                switch nodes[i] {
                case .shape(var s):
                    s.attributes.svgID = nil
                    s.attributes.extras.removeAll { $0.name == "data-name" }
                    nodes[i] = .shape(s)
                case .group(var g):
                    g.attributes.svgID = nil
                    g.attributes.extras.removeAll { $0.name == "data-name" }
                    walk(&g.children)
                    nodes[i] = .group(g)
                case .raw:
                    break
                }
            }
        }
        walk(&out.nodes)
        return out
    }

    // MARK: flatten

    /// `parent · child` in SVG order: applying the result equals applying
    /// `child` first, then `parent`.
    static func compose(_ a: [Double], _ b: [Double]) -> [Double] {
        [
            a[0] * b[0] + a[2] * b[1],
            a[1] * b[0] + a[3] * b[1],
            a[0] * b[2] + a[2] * b[3],
            a[1] * b[2] + a[3] * b[3],
            a[0] * b[4] + a[2] * b[5] + a[4],
            a[1] * b[4] + a[3] * b[5] + a[5],
        ]
    }

    static func composed(_ parent: TransformValue?, _ child: TransformValue?)
        -> TransformValue?
    {
        switch (parent, child) {
        case (nil, nil): return nil
        case (let p?, nil): return p
        case (nil, let c?): return c
        case (let p?, let c?):
            let m = compose(p.matrix, c.matrix)
            return TransformValue(
                raw: "matrix(\(m.map { SVGNum.text($0) }.joined(separator: " ")))", matrix: m)
        }
    }

    /// Parent declarations first, node declarations override (CSS cascade).
    static func mergedStyle(_ parent: Style, _ child: Style) -> Style {
        guard !parent.declarations.isEmpty else { return child }
        var out = parent
        for d in child.declarations { out.set(d.name, d.value) }
        return out
    }

    /// Bake transforms into geometry, expand primitives to paths and dissolve
    /// groups into the parent, preserving order. Group styles merge into their
    /// children (child declarations win); raw nodes pass through unchanged.
    /// Note: group `opacity` merges by override, not multiplication — the icon
    /// corpus never nests opacities.
    static func flatten(_ doc: GraphicDocument) -> GraphicDocument {
        var out = doc
        func dissolve(
            _ nodes: [GraphicNode], style parentStyle: Style,
            transform parentTransform: TransformValue?
        ) -> [GraphicNode] {
            var result: [GraphicNode] = []
            for node in nodes {
                switch node {
                case .shape(var s):
                    s.style = mergedStyle(parentStyle, s.style)
                    s.transform = composed(parentTransform, s.transform)
                    s.kind = .path(Editing2.bakedPaths(of: s))
                    s.transform = nil
                    result.append(.shape(s))
                case .group(let g):
                    result.append(
                        contentsOf: dissolve(
                            g.children,
                            style: mergedStyle(parentStyle, g.style),
                            transform: composed(parentTransform, g.transform)))
                case .raw(let r):
                    result.append(.raw(r))
                }
            }
            return result
        }
        out.nodes = dissolve(doc.nodes, style: Style(), transform: nil)
        return out
    }

    // MARK: resize

    /// Uniform scale into a W×H viewBox, centered. Geometry scales in place
    /// (primitives stay primitives — the scale is uniform); nodes with a
    /// transform get the scale composed in front of it; numeric stroke-widths
    /// scale with the geometry (var()/raw widths are left untouched).
    static func resize(_ doc: GraphicDocument, width: Double, height: Double)
        -> GraphicDocument
    {
        let vb = doc.viewBox
        guard vb.width > 0, vb.height > 0 else { return doc }
        let s = min(width / vb.width, height / vb.height)
        let tx = (width - vb.width * s) / 2 - vb.minX * s
        let ty = (height - vb.height * s) / 2 - vb.minY * s
        let scale = TransformValue(
            raw: "matrix(\(SVGNum.text(s)) 0 0 \(SVGNum.text(s)) "
                + "\(SVGNum.text(tx)) \(SVGNum.text(ty)))",
            matrix: [s, 0, 0, s, tx, ty])
        func mapPt(_ p: Pt) -> Pt { scale.apply(p) }
        func mapPath(_ rp: RefinedPath) -> RefinedPath {
            var segments: [RefinedSegment] = []
            segments.reserveCapacity(rp.segments.count)
            for seg in rp.segments {
                switch seg {
                case .line(let to):
                    segments.append(.line(to: mapPt(to)))
                case .cubic(let c1, let c2, let to):
                    segments.append(.cubic(c1: mapPt(c1), c2: mapPt(c2), to: mapPt(to)))
                case .arc(let c, let r, let sa, let ea, let cw):
                    // Uniform positive scale: circles stay circles, angles hold.
                    segments.append(
                        .arc(
                            center: mapPt(c), radius: r * s, startAngle: sa,
                            endAngle: ea, clockwise: cw))
                }
            }
            return RefinedPath(start: mapPt(rp.start), segments: segments, closed: rp.closed)
        }
        func mapKind(_ kind: ShapeKind) -> ShapeKind {
            switch kind {
            case .path(let paths):
                return .path(paths.map(mapPath))
            case .line(let a, let b):
                return .line(mapPt(a), mapPt(b))
            case .polyline(let pts):
                return .polyline(pts.map(mapPt))
            case .polygon(let pts):
                return .polygon(pts.map(mapPt))
            case .rect(let x, let y, let w, let h, let rx, let ry):
                let o = mapPt(Pt(x, y))
                return .rect(
                    x: o.x, y: o.y, width: w * s, height: h * s,
                    rx: rx.map { $0 * s }, ry: ry.map { $0 * s })
            case .circle(let c, let r):
                return .circle(center: mapPt(c), r: r * s)
            case .ellipse(let c, let rx, let ry):
                return .ellipse(center: mapPt(c), rx: rx * s, ry: ry * s)
            }
        }
        var out = doc
        func walk(_ nodes: inout [GraphicNode]) {
            for i in nodes.indices {
                switch nodes[i] {
                case .shape(var sh):
                    if sh.transform != nil {
                        sh.transform = composed(scale, sh.transform)
                    } else {
                        sh.kind = mapKind(sh.kind)
                    }
                    nodes[i] = .shape(sh)
                case .group(var g):
                    if g.transform != nil {
                        g.transform = composed(scale, g.transform)
                    } else {
                        walk(&g.children)
                    }
                    nodes[i] = .group(g)
                case .raw:
                    break
                }
            }
        }
        walk(&out.nodes)
        out = mapStyles(out) { style in
            for i in style.declarations.indices
            where style.declarations[i].name == "stroke-width" {
                if case .number(let n, let u) = style.declarations[i].value {
                    style.declarations[i].value = .number(n * s, unit: u)
                }
            }
        }
        out.viewBox = ViewBox(minX: 0, minY: 0, width: width, height: height)
        return out
    }

    // MARK: outline-strokes

    /// Expand constant-width strokes into filled outlines. Each stroked shape
    /// is baked (`Editing2.bakedPaths`), outlined by `StrokeOutliner`, and its
    /// stroke styling becomes a fill of the former stroke paint. A shape that
    /// also carries a visible fill keeps its original geometry (stroke props
    /// dropped) and gains a sibling outline node right after it, preserving
    /// paint order. Stroke paint/width inherited from ancestor groups is
    /// honoured; run `flatten` first for fully group-free output.
    static func outlineStrokes(_ doc: GraphicDocument) -> GraphicDocument {
        var out = doc
        var nextID = doc.nextNodeID
        func takeID() -> Int {
            defer { nextID += 1 }
            return nextID
        }
        func capOf(_ style: Style) -> LineCap {
            if case .keyword(let k)? = style.value(of: "stroke-linecap"),
                let cap = LineCap(rawValue: k)
            {
                return cap
            }
            return .butt
        }
        func walk(_ nodes: inout [GraphicNode], inherited: Style) {
            var i = 0
            while i < nodes.count {
                switch nodes[i] {
                case .group(var g):
                    walk(&g.children, inherited: mergedStyle(inherited, g.style))
                    nodes[i] = .group(g)
                case .raw:
                    break
                case .shape(let s):
                    let effective = mergedStyle(inherited, s.effectiveStyle)
                    guard let strokePaint = effective.stroke else { break }
                    if case PaintValue.none = strokePaint { break }
                    let width = effective.strokeWidth ?? 1
                    guard width > 0 else { break }
                    let rings = StrokeOutliner.outline(
                        paths: Editing2.bakedPaths(of: s), width: width,
                        cap: capOf(effective))
                    guard !rings.isEmpty else { break }

                    // Stroke supplied by an ancestor group or a document
                    // class rule, not by the node's own inline style.
                    let strokeInherited = s.style.stroke == nil

                    var outlineStyle = s.style
                    for prop in [
                        "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
                        "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset",
                    ] {
                        outlineStyle.remove(prop)
                    }
                    // stroke-opacity carries over as the outline's fill-opacity.
                    if case .number(let so, let u)? = effective.value(of: "stroke-opacity") {
                        outlineStyle.remove("stroke-opacity")
                        outlineStyle.set("fill-opacity", .number(so, unit: u))
                    }
                    outlineStyle.set("fill", .paint(strokePaint))
                    if strokeInherited {
                        // An ancestor group still declares the stroke; make
                        // sure the outline is not stroked again.
                        outlineStyle.set("stroke", .paint(PaintValue.none))
                    }

                    let hasVisibleFill: Bool
                    if let fill = effective.fill {
                        if case PaintValue.none = fill {
                            hasVisibleFill = false
                        } else {
                            hasVisibleFill = true
                        }
                    } else {
                        hasVisibleFill = false
                    }

                    if hasVisibleFill {
                        var keep = s
                        for prop in [
                            "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
                            "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset",
                            "stroke-opacity",
                        ] {
                            keep.style.remove(prop)
                        }
                        if strokeInherited {
                            keep.style.set("stroke", .paint(PaintValue.none))
                        }
                        var outlineStyleForSibling = outlineStyle
                        // The sibling represents ONLY the stroke: it must not
                        // inherit the shape's fill declaration text.
                        outlineStyleForSibling.remove("opacity")
                        let outline = ShapeNode(
                            id: takeID(), kind: .path(rings),
                            style: outlineStyleForSibling)
                        nodes[i] = .shape(keep)
                        nodes.insert(.shape(outline), at: i + 1)
                        i += 1
                    } else {
                        var replaced = s
                        replaced.kind = .path(rings)
                        replaced.transform = nil
                        replaced.style = outlineStyle
                        // The outline already IS the painted area; an explicit
                        // `fill: none` from the source would hide it.
                        if case .paint(let f)? = replaced.style.value(of: "fill"),
                            case PaintValue.none = f
                        {
                            replaced.style.set("fill", .paint(strokePaint))
                        }
                        nodes[i] = .shape(replaced)
                    }
                }
                i += 1
            }
        }
        walk(&out.nodes, inherited: Style())
        return out
    }
}
