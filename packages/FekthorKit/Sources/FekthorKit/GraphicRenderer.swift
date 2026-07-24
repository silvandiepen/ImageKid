import CoreGraphics
import Foundation

/// Engine-side CoreGraphics renderer for Document Model v2 (`GraphicDocument`).
///
/// Mirrors the app's `ThumbnailRenderer` / `EditorCanvasView.drawNodes`
/// semantics so preview, thumbnails and export cannot diverge:
/// - groups compose transform and multiply opacity onto their children;
/// - shapes draw `CGPathBuilder.path(for:)` under their own transform;
/// - fills honour `fill-rule` (evenodd/nonzero) and `fill-opacity`, and the
///   SVG default black fill applies when no fill is declared (lines and
///   polylines cannot fill);
/// - `.linear` / `.radial` paints draw real `CGGradient`s clipped to the
///   shape; `.raw` / `var()` / `currentColor` / `.reference` fall back to
///   `PaintValue.renderColor` exactly like the app does;
/// - strokes honour width, `stroke-linecap`, `stroke-linejoin`,
///   `stroke-opacity` and `stroke-dasharray`/`stroke-dashoffset`;
/// - styling comes from `renderStyle` — presentation attributes layered
///   beneath class/inline per the SVG cascade — and `display: none` nodes
///   (and their subtrees) are skipped.
///
/// The background is transparent by default; pass `background` for an opaque
/// artboard colour. All drawing happens in document (viewBox) coordinates —
/// the context is flipped to a top-left origin first, so `Pt` maps directly.
public enum GraphicRenderer {
    /// How a document maps into a fixed-size target.
    public enum Fit: Sendable {
        /// Uniform scale so the whole viewBox is visible, centred; the
        /// remaining area stays background (letterbox).
        case contain
    }

    // MARK: - Bitmap rendering

    /// Render the document at `scale` document-units-per-pixel⁻¹: the output
    /// is `viewBox.size * scale` pixels, no margin. Transparent background
    /// unless `background` is given.
    public static func render(_ doc: GraphicDocument, scale: Double = 1, background: RGB? = nil)
        -> CGImage?
    {
        let vb = doc.viewBox
        guard vb.width > 0, vb.height > 0, scale > 0 else { return nil }
        let w = Int((vb.width * scale).rounded())
        let h = Int((vb.height * scale).rounded())
        guard w > 0, h > 0 else { return nil }
        return render(
            doc, width: w, height: h,
            content: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
            background: background)
    }

    /// Render into an exact pixel size; the viewBox is fitted per `fit`
    /// (letterboxed for `.contain`) and the uncovered area stays background.
    public static func render(
        _ doc: GraphicDocument, width: Int, height: Int, fit: Fit = .contain,
        background: RGB? = nil
    ) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        guard
            let content = contentRect(
                for: doc.viewBox, in: CGSize(width: width, height: height), fit: fit)
        else { return nil }
        return render(doc, width: width, height: height, content: content, background: background)
    }

    /// The letterboxed content rectangle for a viewBox in a target size
    /// (top-left-origin coordinates), or nil for a degenerate viewBox.
    public static func contentRect(for vb: ViewBox, in size: CGSize, fit: Fit) -> CGRect? {
        guard vb.width > 0, vb.height > 0, size.width > 0, size.height > 0 else { return nil }
        switch fit {
        case .contain:
            let s = min(size.width / CGFloat(vb.width), size.height / CGFloat(vb.height))
            let w = s * CGFloat(vb.width)
            let h = s * CGFloat(vb.height)
            return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        }
    }

    static func render(
        _ doc: GraphicDocument, width: Int, height: Int, content: CGRect, background: RGB?
    ) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if let background {
            ctx.setFillColor(cgColor(background, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        draw(doc, in: ctx, contextHeight: CGFloat(height), content: content)
        return ctx.makeImage()
    }

    // MARK: - Shared drawing (bitmap AND vector contexts)

    /// Draw the document into any bottom-left-origin CG context (bitmap or
    /// PDF), mapping the viewBox onto `content` expressed in top-left-origin
    /// coordinates of a `contextHeight`-tall page. The same code path renders
    /// pixels and vector PDF, so the two cannot diverge.
    public static func draw(
        _ doc: GraphicDocument, in ctx: CGContext, contextHeight: CGFloat, content: CGRect
    ) {
        let vb = doc.viewBox
        guard vb.width > 0, vb.height > 0, content.width > 0, content.height > 0 else { return }
        ctx.saveGState()
        // Flip to a top-left origin so document coordinates map directly.
        ctx.translateBy(x: 0, y: contextHeight)
        ctx.scaleBy(x: 1, y: -1)
        // Map the viewBox onto the content rect (non-uniform only if the
        // caller asked for it; `contentRect(for:in:fit:)` keeps it uniform).
        ctx.translateBy(x: content.minX, y: content.minY)
        ctx.scaleBy(x: content.width / CGFloat(vb.width), y: content.height / CGFloat(vb.height))
        ctx.translateBy(x: -CGFloat(vb.minX), y: -CGFloat(vb.minY))
        drawNodes(doc.nodes, in: ctx, opacity: 1)
        ctx.restoreGState()
    }

    /// Mirrors `ThumbnailRenderer.draw` / `EditorCanvasView.drawNodes`:
    /// groups compose transform and opacity; shapes honour `renderStyle`
    /// (presentation attributes beneath class + inline, `display: none`
    /// skips the node), fill-rule, fill-opacity, caps, joins and dashes.
    static func drawNodes(_ nodes: [GraphicNode], in ctx: CGContext, opacity: Double) {
        for node in nodes {
            switch node {
            case .raw:
                continue  // defs/style blocks have no direct rendering
            case .group(let g):
                let groupStyle = g.renderStyle
                if groupStyle.isDisplayNone { continue }  // hidden layer
                ctx.saveGState()
                if let t = g.transform { ctx.concatenate(affine(t)) }
                drawNodes(g.children, in: ctx, opacity: opacity * (groupStyle.opacity ?? 1))
                ctx.restoreGState()
            case .image(let i):
                drawImage(i, in: ctx, opacity: opacity)
            case .shape(let s):
                let style = s.renderStyle
                if style.isDisplayNone { continue }  // hidden layer
                ctx.saveGState()
                if let t = s.transform { ctx.concatenate(affine(t)) }
                let nodeOpacity = opacity * (style.opacity ?? 1)
                let path = CGPathBuilder.path(for: s.kind)
                fill(path, style: style, shape: s, opacity: nodeOpacity, in: ctx)
                stroke(path, style: style, opacity: nodeOpacity, in: ctx)
                ctx.restoreGState()
            }
        }
    }

    // MARK: Images

    /// Draw a placed raster into a document-space (y-down) context. Shared by
    /// the engine renderer and the app's thumbnail renderer so a placed image
    /// looks the same everywhere. Hidden nodes, degenerate rects and hrefs
    /// that carry no readable pixels (external references) draw nothing.
    public static func drawImage(_ node: ImageNode, in ctx: CGContext, opacity: Double) {
        let style = node.renderStyle
        guard !style.isDisplayNone, node.width > 0, node.height > 0,
            let bitmap = ImageEmbed.decode(node.href)
        else { return }
        ctx.saveGState()
        if let t = node.transform { ctx.concatenate(affine(t)) }
        ctx.setAlpha(CGFloat(opacity * (style.opacity ?? 1)))
        // The context runs y-down (document space); flip inside the placement
        // rect so the bitmap is not drawn upside down.
        ctx.translateBy(x: CGFloat(node.x), y: CGFloat(node.y + node.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(
            bitmap,
            in: CGRect(x: 0, y: 0, width: CGFloat(node.width), height: CGFloat(node.height)))
        ctx.restoreGState()
    }

    // MARK: Fill

    static func fill(
        _ path: CGPath, style: Style, shape: ShapeNode, opacity: Double, in ctx: CGContext
    ) {
        guard let paint = style.fill ?? defaultFill(for: shape) else { return }
        var fillOpacity = 1.0
        if case .number(let fo, _)? = style.value(of: "fill-opacity") { fillOpacity = fo }
        let alpha = opacity * fillOpacity
        let evenOdd: Bool
        if case .keyword("evenodd")? = style.value(of: "fill-rule") {
            evenOdd = true
        } else {
            evenOdd = false
        }
        switch paint {
        case .none:
            return
        case .linear(let g):
            drawGradientFill(path, evenOdd: evenOdd, alpha: alpha, in: ctx) { space in
                guard let cg = cgGradient(g.stops, alpha: alpha, space: space) else { return }
                ctx.drawLinearGradient(
                    cg, start: CGPoint(x: g.p0.x, y: g.p0.y), end: CGPoint(x: g.p1.x, y: g.p1.y),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        case .radial(let g):
            drawGradientFill(path, evenOdd: evenOdd, alpha: alpha, in: ctx) { space in
                guard let cg = cgGradient(g.stops, alpha: alpha, space: space) else { return }
                let c = CGPoint(x: g.center.x, y: g.center.y)
                ctx.drawRadialGradient(
                    cg, startCenter: c, startRadius: 0, endCenter: c,
                    endRadius: CGFloat(g.radius),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        case .color, .reference, .raw:
            // Solid colours draw directly; references and raw values fall
            // back to `renderColor` (var() fallback / black), like the app.
            guard let c = paint.renderColor else { return }
            ctx.addPath(path)
            ctx.setFillColor(cgColor(c, alpha: alpha))
            ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
        }
    }

    static func drawGradientFill(
        _ path: CGPath, evenOdd: Bool, alpha: Double, in ctx: CGContext,
        _ body: (CGColorSpace) -> Void
    ) {
        guard alpha > 0, !path.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return
        }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip(using: evenOdd ? .evenOdd : .winding)
        body(space)
        ctx.restoreGState()
    }

    /// SVG default: shapes with no fill declaration fill black (lines and
    /// polylines cannot fill) — matches the editor canvas and thumbnails.
    static func defaultFill(for s: ShapeNode) -> PaintValue? {
        if case .line = s.kind { return nil }
        if case .polyline = s.kind { return nil }
        return .color(r: 0, g: 0, b: 0)
    }

    // MARK: Stroke

    static func stroke(_ path: CGPath, style: Style, opacity: Double, in ctx: CGContext) {
        guard let paint = style.stroke, let c = paint.renderColor else { return }
        var strokeOpacity = 1.0
        if case .number(let so, _)? = style.value(of: "stroke-opacity") { strokeOpacity = so }
        ctx.addPath(path)
        ctx.setStrokeColor(cgColor(c, alpha: opacity * strokeOpacity))
        ctx.setLineWidth(CGFloat(style.strokeWidth ?? 1))
        if case .keyword(let cap)? = style.value(of: "stroke-linecap") {
            ctx.setLineCap(cap == "round" ? .round : cap == "square" ? .square : .butt)
        } else {
            ctx.setLineCap(.butt)
        }
        if case .keyword(let join)? = style.value(of: "stroke-linejoin") {
            ctx.setLineJoin(join == "round" ? .round : join == "bevel" ? .bevel : .miter)
        } else {
            ctx.setLineJoin(.miter)
        }
        if let dashes = dashLengths(style), !dashes.isEmpty {
            var phase: CGFloat = 0
            if case .number(let off, _)? = style.value(of: "stroke-dashoffset") {
                phase = CGFloat(off)
            }
            ctx.setLineDash(phase: phase, lengths: dashes)
        }
        ctx.strokePath()
    }

    /// Parse `stroke-dasharray` (stored raw, comma/space separated, matching
    /// `EditorCanvasView`); nil for absent/none/unparseable.
    static func dashLengths(_ style: Style) -> [CGFloat]? {
        guard case .raw(let dash)? = style.value(of: "stroke-dasharray"), dash != "none" else {
            return nil
        }
        let parts = dash.split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.map { CGFloat($0) }
    }

    // MARK: Small helpers

    static func affine(_ t: TransformValue) -> CGAffineTransform {
        let m = t.matrix
        return CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5])
    }

    static func cgColor(_ c: (r: UInt8, g: UInt8, b: UInt8), alpha: Double) -> CGColor {
        CGColor(
            srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255,
            blue: CGFloat(c.b) / 255, alpha: CGFloat(alpha))
    }

    static func cgGradient(_ stops: [GradientStop], alpha: Double, space: CGColorSpace)
        -> CGGradient?
    {
        guard !stops.isEmpty else { return nil }
        let colors = stops.map { stop -> CGColor in
            let c = stop.color
            let rgb: RGB = c.count > 2 ? (c[0], c[1], c[2]) : (0, 0, 0)
            return cgColor(rgb, alpha: alpha)
        }
        let locations = stops.map { CGFloat($0.offset) }
        return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)
    }
}
