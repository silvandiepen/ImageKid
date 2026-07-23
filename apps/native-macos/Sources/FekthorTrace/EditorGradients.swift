import AppKit
import FekthorKit
import SwiftUI

// Gradient plumbing for the editor. The engine's SVGWriter emits typed
// `.linear`/`.radial` paints as `<defs>` + `url(#grad-N)` references, but
// SVGReader keeps defs as raw passthrough and hands the paint back as
// `.reference` — so a reopened gradient would render black and be
// uneditable. `normalizeGradientReferences` (called once at session open)
// parses the modelled gradients back OUT of the raw defs, retypes every
// resolvable reference and drops the consumed defs node; the writer
// regenerates an equivalent defs block on save, so files stay round-trip
// clean. Foreign defs (gradientTransform, objectBoundingBox units, href,
// stop-opacity, non-gradient elements) are left untouched — those paints
// keep today's read-only "custom paint" behaviour.

// MARK: - Raw <defs> gradient parsing

enum GradientDefs {
    struct Parsed {
        /// id → typed paint, for every fully modelled gradient.
        var gradients: [String: PaintValue] = [:]
        /// True when the defs contained NOTHING but modelled gradients —
        /// only then is it safe to drop the raw node after retyping.
        var fullyModelled = true
    }

    /// Parse one RawNode's XML when it is a `<defs>` fragment. Returns nil
    /// for non-defs raw nodes (style blocks, clipPaths, …).
    static func parse(_ xml: String) -> Parsed? {
        let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<defs") else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        guard parser.parse() else { return nil }
        collector.finishPending()
        return collector.parsed
    }

    private final class Collector: NSObject, XMLParserDelegate {
        var parsed = Parsed()

        private struct Pending {
            var id: String
            var isRadial: Bool
            var attrs: [String: String]
            var stops: [GradientStop] = []
            var clean = true
        }
        private var pending: Pending?

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
            qualifiedName: String?, attributes attrs: [String: String] = [:]
        ) {
            switch name {
            case "defs":
                break
            case "linearGradient", "radialGradient":
                finishPending()
                guard let id = attrs["id"],
                    attrs["gradientUnits"] == "userSpaceOnUse",
                    attrs["gradientTransform"] == nil,
                    attrs["href"] == nil, attrs["xlink:href"] == nil,
                    attrs["spreadMethod"] == nil || attrs["spreadMethod"] == "pad"
                else {
                    parsed.fullyModelled = false
                    pending = nil
                    return
                }
                pending = Pending(id: id, isRadial: name == "radialGradient", attrs: attrs)
            case "stop":
                guard var p = pending else {
                    parsed.fullyModelled = false
                    return
                }
                guard attrs["style"] == nil,
                    attrs["stop-opacity"] == nil || Double(attrs["stop-opacity"]!) == 1,
                    let offset = Self.offset(attrs["offset"]),
                    let c = PaintValue.parseHex(attrs["stop-color"] ?? "")
                else {
                    p.clean = false
                    pending = p
                    return
                }
                p.stops.append(GradientStop(color: (c.r, c.g, c.b), offset: offset))
                pending = p
            default:
                // Anything else inside the defs makes it foreign.
                finishPending()
                parsed.fullyModelled = false
            }
        }

        func parser(
            _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
            qualifiedName: String?
        ) {
            if name == "linearGradient" || name == "radialGradient" {
                finishPending()
            }
        }

        /// Fold the gradient under construction into the result.
        func finishPending() {
            guard let p = pending else { return }
            pending = nil
            guard p.clean, p.stops.count >= 2 else {
                parsed.fullyModelled = false
                return
            }
            func num(_ key: String, _ fallback: Double = 0) -> Double {
                p.attrs[key].flatMap(Double.init) ?? fallback
            }
            if p.isRadial {
                guard p.attrs["fx"] == nil, p.attrs["fy"] == nil else {
                    parsed.fullyModelled = false
                    return
                }
                parsed.gradients[p.id] = .radial(
                    RadialGradient(
                        center: Pt(num("cx"), num("cy")), radius: num("r"),
                        stops: p.stops))
            } else {
                parsed.gradients[p.id] = .linear(
                    LinearGradient(
                        p0: Pt(num("x1"), num("y1")), p1: Pt(num("x2"), num("y2")),
                        stops: p.stops))
            }
        }

        /// "0.4" or "40%" → 0.4.
        private static func offset(_ text: String?) -> Double? {
            guard let text else { return nil }
            if text.hasSuffix("%") {
                return Double(text.dropLast()).map { $0 / 100 }
            }
            return Double(text)
        }
    }
}

// MARK: - Session: reference → typed gradient normalization

extension EditorSession {
    /// Retype `url(#id)` fills/strokes whose defs are fully modelled
    /// gradients, then drop those defs nodes — the writer regenerates them
    /// on save. Runs once at open; NOT an edit (no dirty, no history).
    ///
    /// Conservative by construction: a defs node is only consumed when (a)
    /// it contains NOTHING but fully modelled gradients, and (b) none of
    /// its ids is referenced from anywhere we cannot rewrite — class-rule
    /// styles or raw XML fragments. Anything else is left byte-identical,
    /// so foreign files never lose a def they still need (and the writer's
    /// fresh `grad-N` ids can never collide with a def we kept).
    func normalizeGradientReferences() {
        // Ids referenced from places the writer will not rewrite.
        var pinned: Set<String> = []
        func collectPinned(_ nodes: [GraphicNode]) {
            for node in nodes {
                switch node {
                case .raw(let raw):
                    // Cheap but safe: any url(# mention inside raw XML
                    // (clipPaths, <use>, style blocks) pins ALL its ids.
                    if raw.xml.contains("url(#") {
                        pinned.insert("*")
                    }
                case .group(let g):
                    // Presentation attributes are written verbatim — a
                    // url(#) there must keep its def.
                    if g.attributes.extras.contains(where: { $0.value.contains("url(#") }) {
                        pinned.insert("*")
                    }
                    collectPinned(g.children)
                case .shape(let s):
                    if s.attributes.extras.contains(where: { $0.value.contains("url(#") }) {
                        pinned.insert("*")
                    }
                    // Un-modelled declaration values (fill fallbacks,
                    // clip-path, filter) are serialized verbatim too.
                    if s.style.declarations.contains(where: { d in
                        if case .raw(let r) = d.value { return r.contains("url(#") }
                        return false
                    }) {
                        pinned.insert("*")
                    }
                    guard let cls = s.classStyle else { continue }
                    for paint in [cls.fill, cls.stroke] {
                        if case .reference(let id)? = paint { pinned.insert(id) }
                    }
                }
            }
        }
        collectPinned(document.nodes)

        var table: [String: PaintValue] = [:]
        var consumableRawIDs: Set<Int> = []
        for node in document.nodes {
            guard case .raw(let raw) = node, let parsed = GradientDefs.parse(raw.xml),
                parsed.fullyModelled, !parsed.gradients.isEmpty,
                !pinned.contains("*"),
                pinned.isDisjoint(with: parsed.gradients.keys)
            else { continue }
            table.merge(parsed.gradients) { a, _ in a }
            consumableRawIDs.insert(raw.id)
        }
        guard !table.isEmpty else { return }

        var retyped = false
        func retype(_ nodes: inout [GraphicNode]) {
            for i in nodes.indices {
                switch nodes[i] {
                case .raw: continue
                case .group(var g):
                    retype(&g.children)
                    nodes[i] = .group(g)
                case .shape(var s):
                    var touched = false
                    if case .reference(let id)? = s.style.fill, let paint = table[id] {
                        s.style.fill = paint
                        touched = true
                    }
                    if case .reference(let id)? = s.style.stroke, let paint = table[id] {
                        s.style.stroke = paint
                        touched = true
                    }
                    if touched {
                        nodes[i] = .shape(s)
                        retyped = true
                    }
                }
            }
        }
        var doc = document
        retype(&doc.nodes)
        guard retyped else { return }
        doc.nodes.removeAll {
            if case .raw(let raw) = $0 { return consumableRawIDs.contains(raw.id) }
            return false
        }
        document = doc
    }

    // MARK: Fill paint type (Solid | Linear | Radial | None)

    enum GradientKind {
        case linear
        case radial
    }

    /// Switch every selected shape's fill to a gradient. An existing
    /// gradient converts in place (stops kept, geometry derived); a solid
    /// fill becomes a tasteful two-stop ramp — the colour to its darker
    /// variant — spanning the shape's own bounds (left→right for linear,
    /// centre-out for radial). One undo step.
    func setSelectionFillGradient(_ kind: GradientKind) {
        let shapes = selectionShapes()
        if shapes.isEmpty {
            // Nothing selected: seed the drawing style over the artboard.
            var next = drawingStyle
            next.fill = Self.gradientPaint(
                kind, from: next.fill, fallback: next.stroke,
                bounds: (
                    document.viewBox.minX, document.viewBox.minY,
                    document.viewBox.minX + document.viewBox.width,
                    document.viewBox.minY + document.viewBox.height
                ))
            drawingStyle = next
            return
        }
        beginGesture(label: kind == .linear ? "Linear gradient" : "Radial gradient")
        updateShapes(
            shapes.map { shape in
                var s = shape
                let b =
                    Editing2.bounds(of: shape)
                    ?? (
                        document.viewBox.minX, document.viewBox.minY,
                        document.viewBox.minX + document.viewBox.width,
                        document.viewBox.minY + document.viewBox.height
                    )
                s.style.fill = Self.gradientPaint(
                    kind, from: shape.effectiveStyle.fill,
                    fallback: shape.effectiveStyle.stroke, bounds: b)
                return s
            })
        status = "Fill is now a \(kind == .linear ? "linear" : "radial") gradient."
        endStyleEdit()
    }

    /// The gradient a paint converts into: existing gradients keep their
    /// stops and derive the other geometry; plain colours ramp to their
    /// darker variant across `bounds`.
    static func gradientPaint(
        _ kind: GradientKind, from current: PaintValue?, fallback: PaintValue?,
        bounds b: (minX: Double, minY: Double, maxX: Double, maxY: Double)
    ) -> PaintValue {
        let midY = (b.minY + b.maxY) / 2
        let center = Pt((b.minX + b.maxX) / 2, midY)
        let radius = max(b.maxX - b.minX, b.maxY - b.minY) / 2
        // Convert between gradient kinds, keeping the stops.
        switch (current, kind) {
        case (.linear(let g), .radial):
            let c = Pt((g.p0.x + g.p1.x) / 2, (g.p0.y + g.p1.y) / 2)
            let r = max(1e-6, hypot(g.p1.x - g.p0.x, g.p1.y - g.p0.y) / 2)
            return .radial(RadialGradient(center: c, radius: r, stops: g.stops))
        case (.radial(let g), .linear):
            return .linear(
                LinearGradient(
                    p0: Pt(g.center.x - g.radius, g.center.y),
                    p1: Pt(g.center.x + g.radius, g.center.y), stops: g.stops))
        case (.linear(let g), .linear):
            return .linear(g)
        case (.radial(let g), .radial):
            return .radial(g)
        default:
            break
        }
        // Fresh ramp from the current colour (fill, else stroke, else a
        // neutral grey): colour → its darker variant.
        let base: (r: UInt8, g: UInt8, b: UInt8) =
            current?.renderColor ?? fallback?.renderColor ?? (r: 128, g: 128, b: 128)
        let dark = (
            r: UInt8(Double(base.r) * 0.45), g: UInt8(Double(base.g) * 0.45),
            b: UInt8(Double(base.b) * 0.45)
        )
        let stops = [
            GradientStop(color: (base.r, base.g, base.b), offset: 0),
            GradientStop(color: (dark.r, dark.g, dark.b), offset: 1),
        ]
        switch kind {
        case .linear:
            return .linear(
                LinearGradient(p0: Pt(b.minX, midY), p1: Pt(b.maxX, midY), stops: stops))
        case .radial:
            return .radial(RadialGradient(center: center, radius: radius, stops: stops))
        }
    }

    /// Collapse a gradient fill back to a solid colour (its first stop).
    func setSelectionFillSolid() {
        editSelectionStyle("fill", label: "Fill colour") { style in
            let c = style.fill?.renderColor ?? (r: 0, g: 0, b: 0)
            style.fill = .color(r: c.r, g: c.g, b: c.b)
        }
        endStyleEdit()
    }
}

// MARK: - PaintValue gradient conveniences (palette + canvas handles)

extension PaintValue {
    var gradientStops: [GradientStop]? {
        switch self {
        case .linear(let g): return g.stops
        case .radial(let g): return g.stops
        default: return nil
        }
    }

    /// The same gradient with replacement stops (sorted by offset).
    func withGradientStops(_ stops: [GradientStop]) -> PaintValue {
        let sorted = stops.sorted { $0.offset < $1.offset }
        switch self {
        case .linear(var g):
            g.stops = sorted
            return .linear(g)
        case .radial(var g):
            g.stops = sorted
            return .radial(g)
        default:
            return self
        }
    }

    /// The colour the gradient shows at `t` (0…1) — used when a click on
    /// the stops bar inserts an interpolated stop.
    func interpolatedColor(at t: Double) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard let stops = gradientStops, let first = stops.first, let last = stops.last
        else { return nil }
        func rgb(_ s: GradientStop) -> (Double, Double, Double) {
            let c = s.color
            return (
                Double(c.count > 0 ? c[0] : 0), Double(c.count > 1 ? c[1] : 0),
                Double(c.count > 2 ? c[2] : 0)
            )
        }
        if t <= first.offset {
            let c = rgb(first)
            return (UInt8(c.0), UInt8(c.1), UInt8(c.2))
        }
        if t >= last.offset {
            let c = rgb(last)
            return (UInt8(c.0), UInt8(c.1), UInt8(c.2))
        }
        for i in 1..<stops.count where t <= stops[i].offset {
            let a = stops[i - 1]
            let b = stops[i]
            let span = max(1e-9, b.offset - a.offset)
            let k = (t - a.offset) / span
            let ca = rgb(a)
            let cb = rgb(b)
            return (
                UInt8(max(0, min(255, ca.0 + (cb.0 - ca.0) * k))),
                UInt8(max(0, min(255, ca.1 + (cb.1 - ca.1) * k))),
                UInt8(max(0, min(255, ca.2 + (cb.2 - ca.2) * k)))
            )
        }
        return nil
    }
}
