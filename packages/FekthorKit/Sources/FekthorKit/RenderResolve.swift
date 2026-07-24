/// SVG styles a node with three layers: presentation attributes (lowest),
/// CSS class rules, then the inline `style` attribute. `effectiveStyle`
/// merges the top two; presentation attributes survive only as passthrough
/// `attributes.extras` — which is exactly how the trace exporter styles its
/// output (`fill="none" stroke="#…" stroke-width="…"`). These helpers fold
/// the styling presentation attributes back in as the lowest-priority layer
/// so every renderer (engine PNG/PDF export, app canvas, thumbnails) draws
/// such files correctly instead of empty — and all of them agree.
private let presentationStyleNames: Set<String> = [
    "fill", "fill-opacity", "fill-rule",
    "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
    "stroke-dasharray", "stroke-miterlimit", "stroke-opacity",
    "opacity", "display",
]

extension Style {
    /// This style with a node's SVG presentation attributes merged in
    /// BENEATH it (presentation attributes lose to class rules and inline
    /// style per the SVG cascade). Non-styling extras pass through untouched.
    public func resolvedForRender(with attributes: NodeAttributes) -> Style {
        var css = ""
        for attr in attributes.extras where presentationStyleNames.contains(attr.name) {
            css += "\(attr.name): \(attr.value);"
        }
        guard !css.isEmpty else { return self }
        var merged = SVGStyle.parse(css)
        for d in declarations { merged.set(d.name, d.value) }
        return merged
    }

    /// `display: none` — the Layers palette's hide flag. Unknown properties
    /// are kept verbatim (`.raw`), so both forms are checked.
    public var isDisplayNone: Bool {
        switch value(of: "display") {
        case .raw("none")?, .keyword("none")?: return true
        default: return false
        }
    }
}

extension ShapeNode {
    /// `effectiveStyle` with the node's SVG presentation attributes merged
    /// in beneath it. Use this wherever a shape is RENDERED; keep edits on
    /// `style` so files round-trip untouched.
    public var renderStyle: Style {
        effectiveStyle.resolvedForRender(with: attributes)
    }
}

extension GroupNode {
    /// The group's style with its presentation attributes layered beneath
    /// (a `<g opacity="0.5">` should dim its children).
    public var renderStyle: Style {
        style.resolvedForRender(with: attributes)
    }
}

extension ImageNode {
    /// A placed raster's style with its presentation attributes layered
    /// beneath (opacity and `display` are the ones that matter here).
    public var renderStyle: Style {
        style.resolvedForRender(with: attributes)
    }
}

extension GraphicNode {
    /// Hidden for rendering/hit-testing: the node's render style (inline
    /// style + presentation attributes + class rules) says `display: none`.
    public var isHiddenNode: Bool {
        switch self {
        case .shape(let s): return s.renderStyle.isDisplayNone
        case .group(let g): return g.renderStyle.isDisplayNone
        case .image(let i): return i.renderStyle.isDisplayNone
        case .raw: return false
        }
    }
}
