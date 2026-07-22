import FekthorKit

/// SVG styles a node with three layers: presentation attributes (lowest),
/// CSS class rules, then the inline `style` attribute. The engine's
/// `effectiveStyle` merges the top two; presentation attributes survive only
/// as passthrough `attributes.extras` — which is exactly how the trace
/// exporter styles its output (`fill="none" stroke="#…" stroke-width="…"`).
/// These helpers fold the styling presentation attributes back in as the
/// lowest-priority layer so canvases and thumbnails render such files
/// correctly instead of empty.
private let presentationStyleNames: Set<String> = [
    "fill", "fill-opacity", "fill-rule",
    "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
    "stroke-dasharray", "stroke-miterlimit", "stroke-opacity",
    "opacity",
]

private func layered(_ base: Style, under extras: [XMLAttr]) -> Style {
    var css = ""
    for attr in extras where presentationStyleNames.contains(attr.name) {
        css += "\(attr.name): \(attr.value);"
    }
    guard !css.isEmpty else { return base }
    var merged = SVGStyle.parse(css)
    for d in base.declarations { merged.set(d.name, d.value) }
    return merged
}

extension ShapeNode {
    /// `effectiveStyle` with the node's SVG presentation attributes merged
    /// in beneath it. Use this wherever a shape is RENDERED; keep edits on
    /// `style` so files round-trip untouched.
    var renderStyle: Style {
        layered(effectiveStyle, under: attributes.extras)
    }
}

extension GroupNode {
    /// The group's style with its presentation attributes layered beneath
    /// (a `<g opacity="0.5">` should dim its children).
    var renderStyle: Style {
        layered(style, under: attributes.extras)
    }
}
