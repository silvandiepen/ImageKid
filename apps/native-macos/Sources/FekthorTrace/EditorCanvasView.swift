import AppKit
import FekthorKit
import SwiftUI

/// The editor canvas for an `EditorSession`: renders the GraphicDocument
/// tree (groups with transforms and opacity, primitives, class-resolved
/// styles) and provides the editing interactions — click/⇧-click selection,
/// marquee, anchor and Bézier-handle drags, body drags to move, selection
/// transform handles (scale + rotate lollipop), shape-drawing tools, and
/// right-click point removal. Zoom/offset bindings share the app's
/// navigation gestures.
/// Workspace grid on the editor canvas: spacing/subdivisions in artboard
/// units, a visibility flag (⌘' — hiding never erases the spacing) and
/// snapping (⇧⌘'; hold ⌃ to disable while dragging). Trace-mode canvases
/// never get one.
struct EditorGridConfig: Equatable {
    var spacing: Double
    var subdivisions: Int
    var visible: Bool
    var snap: Bool
    /// Workspace "Grid strength" multiplier on the line opacities
    /// (1 = standard; the draw clamps so heavy values never overwhelm).
    var opacity: Double = 1
}

/// The workspace guide icon drawn dimmed between the artboard fill and the
/// grid: a shared construction template (key lines, safe areas) behind
/// every icon. Never hit-tested, never saved — pure canvas chrome. The
/// guide SVG scales to the artboard viewBox (contain, centred).
struct EditorGuideConfig: Equatable {
    var document: GraphicDocument
    var visible: Bool
}

struct EditorCanvasView: View {
    @ObservedObject var session: EditorSession
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize
    var grid: EditorGridConfig? = nil
    /// The workspace guide icon (View ▸ Show Guide); nil when the open file
    /// IS the guide, or no workspace/guide is configured.
    var guide: EditorGuideConfig? = nil
    /// View ▸ Snap to Points (⌥⌘'): dragged anchors, drawn shapes and moved
    /// selections magnet onto other shapes' anchors and bounds
    /// corners/centres. Point snap WINS over grid snap; ⌃ disables both.
    var snapToPoints: Bool = false

    @State private var activeAnchor: (path: Int, index: Int)? = nil
    @State private var draggingAnchor: (path: Int, index: Int)? = nil
    @State private var draggingHandle: (segment: Int, kind: Editing.HandleKind)? = nil
    @State private var draggingBody = false
    /// Body-drag bookkeeping: the doc point the drag started at, and the
    /// delta applied so far. Snapping quantises the CUMULATIVE delta (the
    /// shape keeps its offset and moves in grid steps) instead of each point.
    @State private var moveOrigin: Pt? = nil
    @State private var moveApplied = Pt(0, 0)
    @State private var gestureBegan = false
    @State private var transformDrag: TransformDrag? = nil
    @State private var marqueeRect: CGRect? = nil
    @State private var marqueeBase: Set<Int> = []
    @State private var drawStart: Pt? = nil
    @State private var drawDraft: ShapeKind? = nil
    /// Pen-tool gesture state. The press APPENDS the anchor (session state);
    /// these only track the in-flight gesture: whether the press landed on
    /// the first anchor (close), whether the drag has pulled handles out,
    /// and the cursor for the rubber-band preview.
    @State private var penClosing = false
    @State private var penDragging = false
    @State private var penHover: CGPoint? = nil
    /// The pointer is over the canvas (hover phase) — the tool cursor is
    /// only ours to set while this is true.
    @State private var pointerOverCanvas = false
    /// In-flight gradient annotator drag: which handle of which shape, and
    /// the paint as it was at drag start — every event recomputes from it
    /// so nothing accumulates. One "Gradient" undo step per drag.
    @State private var gradientDrag: GradientDragState? = nil
    /// The Free Distort corner being dragged (session.distort holds the
    /// originals/corners; this is only the gesture's pick).
    @State private var distortCorner: Int? = nil
    /// In-flight corner-dot drag (live corner radius): the shape as it was
    /// at drag start — every event re-fillets from this original so nothing
    /// compounds — plus the picked corner's geometry. One undo step.
    @State private var cornerDrag: CornerDrag? = nil

    private struct CornerDrag {
        var originals: [ShapeNode]
        /// The picked dot's subpath, anchor index, anchor position and unit
        /// interior bisector (the drag axis: distance along it = radius).
        var path: Int
        var index: Int
        var anchor: Pt
        var bisector: Pt
        /// nil = round every corner (shape-level selection); a map = only
        /// the picked corner (a specific point was selected).
        var only: [Int: Set<Int>]?
    }

    /// Corner dots sit this far outside the anchor, along the interior
    /// bisector (screen points).
    private let cornerDotOffset: CGFloat = 11
    /// Snap-to-points candidates (doc space), collected ONCE at gesture
    /// start from the non-dragged shapes: anchors + bounds corners/centres.
    @State private var snapMagnets: [Pt] = []
    /// The magnet the drag is currently stuck to — drawn as an accent cross.
    @State private var activeMagnet: Pt? = nil

    private let hitRadius: CGFloat = 8
    /// The selection frame sits this far outside the geometry so its scale
    /// handles do not shadow the shape's own corner anchors.
    private let boxPad: CGFloat = 6

    private var single: Int? {
        session.selection.count == 1 ? session.selection.first : nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(Color(nsColor: .textBackgroundColor))
                canvas(in: geo.size)
                    .overlay(
                        RightClickCatcher { point, size in
                            menuItems(at: point, in: size)
                        }
                    )
            }
            .clipped()
            // Arrow keys nudge the selected point. Focus follows a click on
            // the canvas, so selecting a point makes the keys live.
            .focusable()
            .onKeyPress(.upArrow) { nudgeActiveAnchor(dx: 0, dy: -1) ? .handled : .ignored }
            .onKeyPress(.downArrow) { nudgeActiveAnchor(dx: 0, dy: 1) ? .handled : .ignored }
            .onKeyPress(.leftArrow) { nudgeActiveAnchor(dx: -1, dy: 0) ? .handled : .ignored }
            .onKeyPress(.rightArrow) { nudgeActiveAnchor(dx: 1, dy: 0) ? .handled : .ignored }
        }
        .frame(minWidth: 300, minHeight: 340)
    }

    /// Move the selected point by one step in the given direction. With grid
    /// snapping on the step is one grid unit (and the point lands on the grid);
    /// off, it's a fine 1pt nudge — ⇧ makes either a 10× coarse nudge.
    @discardableResult
    private func nudgeActiveAnchor(dx: Double, dy: Double) -> Bool {
        guard session.tool == .select, let sel = single, let active = activeAnchor,
            let shape = session.document.firstShape(id: sel),
            let anchor = Editing2.anchors(of: shape).first(where: {
                $0.path == active.path && $0.index == active.index
            })
        else { return false }
        let base = snapStep ?? 1
        let step = NSEvent.modifierFlags.contains(.shift) ? base * 10 : base
        let target = Pt(anchor.position.x + dx * step, anchor.position.y + dy * step)
        session.beginGesture(label: "Nudge point")
        session.moveAnchor(node: sel, path: active.path, anchor: active.index, to: snapped(target))
        return true
    }

    private func canvas(in size: CGSize) -> some View {
        let _ = session.generation
        return Canvas { ctx, canvasSize in
            let doc = session.document
            let t = transform(doc: doc, in: canvasSize)
            var cg = CGAffineTransform.identity
            cg = cg.translatedBy(x: t.tx, y: t.ty)
            cg = cg.scaledBy(x: t.s, y: t.s)

            // Artboard.
            let board = CGRect(
                x: t.tx + t.s * doc.viewBox.minX, y: t.ty + t.s * doc.viewBox.minY,
                width: t.s * doc.viewBox.width, height: t.s * doc.viewBox.height)
            ctx.fill(Path(board), with: .color(.white))
            if let guide, guide.visible {
                drawGuide(guide.document, in: &ctx, doc: doc, t: t)
            }
            if let g = grid, g.visible, g.spacing > 0 {
                drawGrid(g, in: &ctx, doc: doc, t: t)
            }
            ctx.stroke(Path(board), with: .color(.gray.opacity(0.4)), lineWidth: 1)

            drawNodes(session.document.nodes, into: &ctx, base: cg, scale: t.s, opacity: 1)

            // Selection highlight.
            for id in session.selection.sorted() {
                if let shape = doc.firstShape(id: id) {
                    var p = Path(shapePath(shape))
                    p = p.applying(cg)
                    ctx.stroke(p, with: .color(.blue.opacity(0.55)), lineWidth: 2)
                }
            }

            drawAnchorsAndHandles(&ctx, doc: doc, t: t)
            drawCornerDots(&ctx, doc: doc, t: t)
            drawSelectionChrome(&ctx, t: t)
            if let gh = gradientHandles(t: t) {
                drawGradientChrome(gh, &ctx)
            }
            if let d = session.distort {
                drawDistortChrome(d, &ctx, t: t)
            }

            // Shape-tool preview.
            if let draft = drawDraft {
                var p = Path(CGPathBuilder.path(for: draft))
                p = p.applying(cg)
                ctx.stroke(p, with: .color(.blue.opacity(0.8)), lineWidth: 1.5)
            }

            // Pen-tool preview: committed segments, rubber band, anchors.
            if session.tool == .pen, !session.penAnchors.isEmpty {
                drawPenPreview(&ctx, base: cg, t: t)
            }

            // Marquee band (view coordinates).
            if let band = marqueeRect {
                ctx.fill(Path(band), with: .color(.blue.opacity(0.08)))
                ctx.stroke(Path(band), with: .color(.blue.opacity(0.6)), lineWidth: 1)
            }

            // Snap-to-points: an accent cross on the magnet the drag is
            // currently stuck to.
            if let m = activeMagnet {
                let v = CGPoint(x: m.x * t.s + t.tx, y: m.y * t.s + t.ty)
                let arm: CGFloat = 5
                var cross = Path()
                cross.move(to: CGPoint(x: v.x - arm, y: v.y))
                cross.addLine(to: CGPoint(x: v.x + arm, y: v.y))
                cross.move(to: CGPoint(x: v.x, y: v.y - arm))
                cross.addLine(to: CGPoint(x: v.x, y: v.y + arm))
                ctx.stroke(cross, with: .color(.fekthorAccent), lineWidth: 1.5)
            }
        }
        .gesture(dragGesture(in: size))
        // Hover drives both the pen preview and the tool cursor. `set()`
        // (never push/pop) cannot leak: every hover event re-asserts the
        // right cursor, leaving restores the arrow, and there is no stack
        // to unbalance. The floating panels sit above this view, so their
        // hit-testing blocks canvas hover — controls keep their own cursors.
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let p):
                pointerOverCanvas = true
                penHover = session.tool == .pen ? p : nil
                ToolCursors.cursor(for: session.tool).set()
            case .ended:
                pointerOverCanvas = false
                penHover = nil
                NSCursor.arrow.set()
            }
        }
        // Tool switches (keyboard letters, ⌘1–5, Esc) retarget the cursor
        // in place — no mouse move needed.
        .onChange(of: session.tool) { _, tool in
            if pointerOverCanvas { ToolCursors.cursor(for: tool).set() }
        }
        .onDisappear {
            if pointerOverCanvas { NSCursor.arrow.set() }
        }
    }

    // MARK: - Grid

    /// Grid lines across the artboard (major every `spacing`, lighter
    /// subdivision lines between), fading in with zoom and skipped entirely
    /// while cells are under ~4pt on screen. A slate blue-grey reads better
    /// on the white artboard than pure gray; the workspace's "Grid strength"
    /// multiplies both line opacities, clamped so cranked-up grids never
    /// overwhelm the artwork.
    private func drawGrid(
        _ g: EditorGridConfig, in ctx: inout GraphicsContext, doc: GraphicDocument, t: T
    ) {
        let majorPx = g.spacing * Double(t.s)
        guard majorPx >= 4 else { return }
        let fade = min(1.0, (majorPx - 4) / 8)
        let line = Color(red: 0.42, green: 0.47, blue: 0.58)
        let strength = max(0, g.opacity)
        let subAlpha = min(0.45, 0.12 * strength) * fade
        let majorAlpha = min(0.45, 0.22 * strength) * fade
        let subs = max(0, g.subdivisions)
        if subs > 0 {
            let subStep = g.spacing / Double(subs + 1)
            if subStep * Double(t.s) >= 4 {
                var p = Path()
                addGridLines(&p, doc: doc, step: subStep, t: t, skipEvery: subs + 1)
                ctx.stroke(p, with: .color(line.opacity(subAlpha)), lineWidth: 0.5)
            }
        }
        var p = Path()
        addGridLines(&p, doc: doc, step: g.spacing, t: t, skipEvery: 0)
        ctx.stroke(p, with: .color(line.opacity(majorAlpha)), lineWidth: 0.5)
    }

    /// Vertical + horizontal lines every `step` across the viewBox. With
    /// `skipEvery` > 0, every Nth line is left out (subdivision passes skip
    /// the positions the major pass draws).
    private func addGridLines(
        _ p: inout Path, doc: GraphicDocument, step: Double, t: T, skipEvery: Int
    ) {
        let vb = doc.viewBox
        let x0 = vb.minX
        let y0 = vb.minY
        let x1 = vb.minX + vb.width
        let y1 = vb.minY + vb.height
        let top = CGFloat(y0) * t.s + t.ty
        let bottom = CGFloat(y1) * t.s + t.ty
        let leading = CGFloat(x0) * t.s + t.tx
        let trailing = CGFloat(x1) * t.s + t.tx
        var i = 0
        while true {
            let x = x0 + Double(i) * step
            if x > x1 + 1e-9 { break }
            if skipEvery == 0 || i % skipEvery != 0 {
                let vx = CGFloat(x) * t.s + t.tx
                p.move(to: CGPoint(x: vx, y: top))
                p.addLine(to: CGPoint(x: vx, y: bottom))
            }
            i += 1
        }
        i = 0
        while true {
            let y = y0 + Double(i) * step
            if y > y1 + 1e-9 { break }
            if skipEvery == 0 || i % skipEvery != 0 {
                let vy = CGFloat(y) * t.s + t.ty
                p.move(to: CGPoint(x: leading, y: vy))
                p.addLine(to: CGPoint(x: trailing, y: vy))
            }
            i += 1
        }
    }

    // MARK: - Guide

    /// The workspace guide SVG, dimmed to ~25% and scaled to the artboard
    /// viewBox (contain, centred). Drawn between the artboard fill and the
    /// grid; never part of the document, never hit-tested.
    private func drawGuide(
        _ g: GraphicDocument, in ctx: inout GraphicsContext, doc: GraphicDocument, t: T
    ) {
        let gvb = g.viewBox
        guard gvb.width > 0, gvb.height > 0 else { return }
        let vb = doc.viewBox
        let k = min(vb.width / gvb.width, vb.height / gvb.height)
        let ox = vb.minX + (vb.width - gvb.width * k) / 2
        let oy = vb.minY + (vb.height - gvb.height * k) / 2
        var base = CGAffineTransform.identity
        base = base.translatedBy(x: t.tx, y: t.ty)
        base = base.scaledBy(x: t.s, y: t.s)
        base = base.translatedBy(x: CGFloat(ox), y: CGFloat(oy))
        base = base.scaledBy(x: CGFloat(k), y: CGFloat(k))
        base = base.translatedBy(x: CGFloat(-gvb.minX), y: CGFloat(-gvb.minY))
        drawNodes(g.nodes, into: &ctx, base: base, scale: t.s * CGFloat(k), opacity: 0.25)
    }

    // MARK: - Snapping

    /// The active snap step in document units — the finest visible grid
    /// (subdivisions when configured). nil when snapping is off or ⌃ is
    /// held (the temporary disable; ⌥ is taken by mirror/centre gestures).
    private var snapStep: Double? {
        guard let g = grid, g.snap, g.spacing > 0,
            !NSEvent.modifierFlags.contains(.control)
        else { return nil }
        let subs = max(0, g.subdivisions)
        return subs > 0 ? g.spacing / Double(subs + 1) : g.spacing
    }

    private func snapped(_ p: Pt) -> Pt {
        guard let step = snapStep else { return p }
        return Pt((p.x / step).rounded() * step, (p.y / step).rounded() * step)
    }

    /// ⇧-snap: snaps to the grid even while the global snap toggle is off —
    /// used for handle drags, where free movement is the default.
    private func forceSnapped(_ p: Pt) -> Pt {
        guard let g = grid, g.spacing > 0 else { return p }
        let subs = max(0, g.subdivisions)
        let step = subs > 0 ? g.spacing / Double(subs + 1) : g.spacing
        return Pt((p.x / step).rounded() * step, (p.y / step).rounded() * step)
    }

    // MARK: - Snap to points

    /// Candidate magnets for the gesture that is starting: every NON-excluded
    /// shape contributes its anchors plus its bounds corners and centre
    /// (groups are walked; excluded = the shapes being dragged). Capped so a
    /// traced document with thousands of anchors cannot stall a drag start.
    private func collectMagnets(excluding excluded: Set<Int>) -> [Pt] {
        guard snapToPoints else { return [] }
        let cap = 600
        var pts: [Pt] = []
        func walk(_ nodes: [GraphicNode]) {
            for node in nodes {
                guard pts.count < cap else { return }
                switch node {
                case .raw: continue
                case .group(let g): walk(g.children)
                case .shape(let s):
                    guard !excluded.contains(s.id) else { continue }
                    for a in Editing2.anchors(of: s) {
                        pts.append(a.position)
                        if pts.count >= cap { return }
                    }
                    if let b = Editing2.bounds(of: s) {
                        pts.append(Pt(b.minX, b.minY))
                        pts.append(Pt(b.maxX, b.minY))
                        pts.append(Pt(b.minX, b.maxY))
                        pts.append(Pt(b.maxX, b.maxY))
                        pts.append(Pt((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2))
                    }
                }
            }
        }
        walk(session.document.nodes)
        return pts
    }

    /// The nearest magnet within ~6pt on screen, or nil. ⌃ disables all
    /// snapping (point and grid alike), matching the grid behaviour.
    private func magnetNear(_ p: Pt, in size: CGSize) -> Pt? {
        guard snapToPoints, !snapMagnets.isEmpty,
            !NSEvent.modifierFlags.contains(.control)
        else { return nil }
        let t = transform(doc: session.document, in: size)
        let tol = 6.0 / Double(t.s)
        var best: (Pt, Double)? = nil
        for m in snapMagnets {
            let d = ((m.x - p.x) * (m.x - p.x) + (m.y - p.y) * (m.y - p.y)).squareRoot()
            if d <= tol, best == nil || d < best!.1 { best = (m, d) }
        }
        return best?.0
    }

    /// Point snap first (it wins), grid snap second. Tracks `activeMagnet`
    /// so the canvas can mark the point the drag is stuck to.
    private func pointOrGridSnapped(_ p: Pt, in size: CGSize) -> Pt {
        if let m = magnetNear(p, in: size) {
            activeMagnet = m
            return m
        }
        activeMagnet = nil
        return snapped(p)
    }

    // MARK: - Rendering

    private func drawNodes(
        _ nodes: [GraphicNode], into ctx: inout GraphicsContext, base: CGAffineTransform,
        scale: CGFloat, opacity: Double
    ) {
        for node in nodes {
            switch node {
            case .raw:
                continue  // defs/style blocks have no direct rendering
            case .group(let g):
                let groupStyle = g.renderStyle
                // Layers hide: display:none skips the whole subtree.
                if groupStyle.isDisplayNone { continue }
                var groupBase = base
                if let t = g.transform {
                    let m = t.matrix
                    groupBase =
                        CGAffineTransform(
                            a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5]
                        ).concatenating(base)
                }
                let groupOpacity = opacity * (groupStyle.opacity ?? 1)
                drawNodes(
                    g.children, into: &ctx, base: groupBase, scale: scale,
                    opacity: groupOpacity)
            case .shape(let s):
                let style = s.renderStyle
                if style.isDisplayNone { continue }
                var shapeBase = base
                if let t = s.transform {
                    let m = t.matrix
                    shapeBase =
                        CGAffineTransform(
                            a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5]
                        ).concatenating(base)
                }
                let nodeOpacity = opacity * (style.opacity ?? 1)
                var p = Path(CGPathBuilder.path(for: s.kind))
                p = p.applying(shapeBase)

                if let fill = style.fill ?? defaultFill(for: s) {
                    var rule = FillStyle(eoFill: false)
                    if case .keyword("evenodd")? = style.value(of: "fill-rule") {
                        rule = FillStyle(eoFill: true)
                    }
                    let fillOpacity: Double
                    if case .number(let fo, _)? = style.value(of: "fill-opacity") {
                        fillOpacity = fo
                    } else {
                        fillOpacity = 1
                    }
                    let alpha = nodeOpacity * fillOpacity
                    if let shading = gradientShading(fill, base: shapeBase, alpha: alpha) {
                        // Real gradient, not a first-stop flattening.
                        ctx.fill(p, with: shading, style: rule)
                    } else if let c = fill.renderColor {
                        ctx.fill(p, with: .color(color(c).opacity(alpha)), style: rule)
                    }
                }
                if let stroke = style.stroke, let c = stroke.renderColor {
                    let width = style.strokeWidth ?? 1
                    // Zero-length round-capped lines are DOTS in SVG; the
                    // path stroke would draw nothing.
                    if case .line(let a, let b) = s.kind, a.x == b.x, a.y == b.y,
                        case .keyword("round")? = style.value(of: "stroke-linecap")
                    {
                        let center = CGPoint(x: a.x, y: a.y).applying(shapeBase)
                        let r = width * scale / 2
                        ctx.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: center.x - r, y: center.y - r,
                                    width: 2 * r, height: 2 * r)),
                            with: .color(color(c).opacity(nodeOpacity)))
                        continue
                    }
                    var strokeStyle = StrokeStyle(lineWidth: width * scale)
                    if case .keyword(let cap)? = style.value(of: "stroke-linecap") {
                        strokeStyle.lineCap =
                            cap == "round" ? .round : cap == "square" ? .square : .butt
                    }
                    if case .keyword(let join)? = style.value(of: "stroke-linejoin") {
                        strokeStyle.lineJoin = join == "round" ? .round : .miter
                    }
                    if case .raw(let dash)? = style.value(of: "stroke-dasharray"), dash != "none" {
                        let parts = dash.split(whereSeparator: { $0 == "," || $0 == " " })
                            .compactMap { Double($0) }
                        if !parts.isEmpty {
                            strokeStyle.dash = parts.map { CGFloat($0) * scale }
                        }
                    }
                    if let shading = gradientShading(stroke, base: shapeBase, alpha: nodeOpacity) {
                        ctx.stroke(p, with: shading, style: strokeStyle)
                    } else {
                        ctx.stroke(
                            p, with: .color(color(c).opacity(nodeOpacity)), style: strokeStyle)
                    }
                }
            }
        }
    }

    /// Anchors + Bézier handles for a single selection.
    private func drawAnchorsAndHandles(
        _ ctx: inout GraphicsContext, doc: GraphicDocument, t: T
    ) {
        guard let sel = single, let shape = doc.firstShape(id: sel) else { return }
        if let active = activeAnchor {
            for h in Editing2.handles(of: shape, path: active.path, anchor: active.index) {
                let hv = CGPoint(x: h.position.x * t.s + t.tx, y: h.position.y * t.s + t.ty)
                let av = CGPoint(x: h.anchor.x * t.s + t.tx, y: h.anchor.y * t.s + t.ty)
                var lever = Path()
                lever.move(to: av)
                lever.addLine(to: hv)
                ctx.stroke(lever, with: .color(.blue.opacity(0.6)), lineWidth: 1)
                let r: CGFloat = 3
                let rect = CGRect(x: hv.x - r, y: hv.y - r, width: 2 * r, height: 2 * r)
                var diamond = Path()
                diamond.move(to: CGPoint(x: hv.x, y: rect.minY))
                diamond.addLine(to: CGPoint(x: rect.maxX, y: hv.y))
                diamond.addLine(to: CGPoint(x: hv.x, y: rect.maxY))
                diamond.addLine(to: CGPoint(x: rect.minX, y: hv.y))
                diamond.closeSubpath()
                ctx.fill(diamond, with: .color(.blue))
            }
        }
        for a in Editing2.anchors(of: shape) {
            let v = CGPoint(x: a.position.x * t.s + t.tx, y: a.position.y * t.s + t.ty)
            let isActive =
                activeAnchor.map { $0.path == a.path && $0.index == a.index } ?? false
            let r: CGFloat = isActive ? 4.5 : 3.5
            let rect = CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rect), with: .color(isActive ? .blue : .white))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.blue), lineWidth: 1.5)
        }
    }

    // MARK: - Live corner dots

    /// The single selected shape's corner dots: one per fillet-able corner
    /// anchor (line-line joints sharper than ~15°), offset INSIDE the
    /// corner along the bisector — Illustrator's live-corner widgets.
    /// Dragging one toward the interior rounds the corner(s) live.
    private func cornerDots(of shape: ShapeNode, t: T)
        -> [(path: Int, info: LiveCorners.CornerInfo, dot: CGPoint)]
    {
        let offset = Double(cornerDotOffset / t.s)
        var out: [(Int, LiveCorners.CornerInfo, CGPoint)] = []
        for (pi, rp) in Editing2.bakedPaths(of: shape).enumerated() {
            for info in LiveCorners.cornerAnchors(of: rp) {
                let p = Pt(
                    info.position.x + info.bisector.x * offset,
                    info.position.y + info.bisector.y * offset)
                out.append(
                    (pi, info, CGPoint(x: p.x * t.s + t.tx, y: p.y * t.s + t.ty)))
            }
        }
        return out
    }

    /// Visually distinct from anchors: smaller, accent-filled circles.
    private func drawCornerDots(_ ctx: inout GraphicsContext, doc: GraphicDocument, t: T) {
        guard session.tool == .select, session.distort == nil,
            let sel = single, let shape = doc.firstShape(id: sel)
        else { return }
        for (_, _, dot) in cornerDots(of: shape, t: t) {
            let r: CGFloat = 2.75
            let rect = CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rect), with: .color(.fekthorAccent))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1)
        }
    }

    /// The selection transform frame: dashed bounding box (padded outward so
    /// its handles clear the shape's own anchors), 8 scale handles, and a
    /// rotate lollipop above the top edge.
    private func drawSelectionChrome(_ ctx: inout GraphicsContext, t: T) {
        guard session.tool == .select, !session.selection.isEmpty,
            session.distort == nil,
            let box = selectionDocBounds()
        else { return }
        let view = paddedViewRect(box, t: t)
        ctx.stroke(
            Path(view), with: .color(.blue.opacity(0.7)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        // Rotate lollipop.
        let knob = rotateKnobPoint(for: view)
        var stem = Path()
        stem.move(to: CGPoint(x: view.midX, y: view.minY))
        stem.addLine(to: knob)
        ctx.stroke(stem, with: .color(.blue.opacity(0.7)), lineWidth: 1)
        let knobRect = CGRect(x: knob.x - 4, y: knob.y - 4, width: 8, height: 8)
        ctx.fill(Path(ellipseIn: knobRect), with: .color(.white))
        ctx.stroke(Path(ellipseIn: knobRect), with: .color(.blue), lineWidth: 1.5)
        // Scale handles.
        for h in BoxHandle.allCases {
            let p = handlePoint(h, in: view)
            let r = CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
            ctx.fill(Path(r), with: .color(.white))
            ctx.stroke(Path(r), with: .color(.blue), lineWidth: 1.2)
        }
    }

    // MARK: - Gradients (rendering + on-canvas handles)

    /// Typed gradient paints as GraphicsContext shadings in view space (the
    /// shape's base transform maps the gradient's user-space geometry).
    /// nil for non-gradient paints — callers fall back to flat colour.
    private func gradientShading(
        _ paint: PaintValue, base: CGAffineTransform, alpha: Double
    ) -> GraphicsContext.Shading? {
        func gradient(_ stops: [GradientStop]) -> Gradient {
            Gradient(
                stops: stops
                    .sorted { $0.offset < $1.offset }
                    .map { stop in
                        Gradient.Stop(
                            color: GradientStopsEditor.color(stop).opacity(alpha),
                            location: CGFloat(max(0, min(1, stop.offset))))
                    })
        }
        switch paint {
        case .linear(let g):
            return .linearGradient(
                gradient(g.stops),
                startPoint: CGPoint(x: g.p0.x, y: g.p0.y).applying(base),
                endPoint: CGPoint(x: g.p1.x, y: g.p1.y).applying(base))
        case .radial(let g):
            let scale = hypot(base.a, base.b)
            return .radialGradient(
                gradient(g.stops),
                center: CGPoint(x: g.center.x, y: g.center.y).applying(base),
                startRadius: 0, endRadius: max(0.01, CGFloat(g.radius) * scale))
        default:
            return nil
        }
    }

    /// The single selected shape's gradient annotator, in view coordinates:
    /// the axis (linear p0→p1; radial centre→radius handle) plus the
    /// INTERIOR stops as chips riding the axis (the end stops are edited
    /// through the endpoints / the palette).
    private struct GradientAnnotator {
        var shapeID: Int
        var paint: PaintValue
        var a: CGPoint
        var b: CGPoint
        var isRadial: Bool
        var stops: [(index: Int, point: CGPoint, stop: GradientStop)]
    }

    private func gradientHandles(t: T) -> GradientAnnotator? {
        guard session.tool == .select, session.distort == nil, let sel = single,
            let shape = session.document.firstShape(id: sel)
        else { return nil }
        let paint = shape.effectiveStyle.fill
        guard let paint, let axis = Self.gradientAxis(paint) else { return nil }
        func view(_ p: Pt) -> CGPoint {
            CGPoint(x: p.x * t.s + t.tx, y: p.y * t.s + t.ty)
        }
        let a = view(axis.0)
        let b = view(axis.1)
        var chips: [(Int, CGPoint, GradientStop)] = []
        for (i, stop) in (paint.gradientStops ?? []).enumerated()
        where stop.offset > 0.001 && stop.offset < 0.999 {
            let p = CGPoint(
                x: a.x + (b.x - a.x) * stop.offset, y: a.y + (b.y - a.y) * stop.offset)
            chips.append((i, p, stop))
        }
        var isRadial = false
        if case .radial = paint { isRadial = true }
        return GradientAnnotator(
            shapeID: sel, paint: paint, a: a, b: b, isRadial: isRadial, stops: chips)
    }

    /// The gradient's editable axis in DOC space: linear p0→p1, radial
    /// centre → the point at (centre.x + radius, centre.y).
    private static func gradientAxis(_ paint: PaintValue) -> (Pt, Pt)? {
        switch paint {
        case .linear(let g): return (g.p0, g.p1)
        case .radial(let g): return (g.center, Pt(g.center.x + g.radius, g.center.y))
        default: return nil
        }
    }

    /// Axis line (white casing under blue core so it reads over any art),
    /// round endpoint handles, and the interior stop chips filled with
    /// their own colours.
    private func drawGradientChrome(_ gh: GradientAnnotator, _ ctx: inout GraphicsContext) {
        var axis = Path()
        axis.move(to: gh.a)
        axis.addLine(to: gh.b)
        ctx.stroke(axis, with: .color(.white.opacity(0.9)), lineWidth: 3)
        ctx.stroke(axis, with: .color(.blue.opacity(0.8)), lineWidth: 1.2)
        if gh.isRadial {
            // The radius ring, faint, so the extent reads at a glance.
            let r = hypot(gh.b.x - gh.a.x, gh.b.y - gh.a.y)
            let ring = CGRect(x: gh.a.x - r, y: gh.a.y - r, width: 2 * r, height: 2 * r)
            ctx.stroke(
                Path(ellipseIn: ring), with: .color(.blue.opacity(0.35)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        for p in [gh.a, gh.b] {
            let rect = CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.blue), lineWidth: 1.5)
        }
        for chip in gh.stops {
            let rect = CGRect(
                x: chip.point.x - 4, y: chip.point.y - 4, width: 8, height: 8)
            ctx.fill(Path(ellipseIn: rect), with: .color(GradientStopsEditor.color(chip.stop)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
            ctx.stroke(
                Path(ellipseIn: rect.insetBy(dx: -1, dy: -1)),
                with: .color(.blue.opacity(0.7)), lineWidth: 1)
        }
    }

    /// One gradient-annotator drag: `paint` is the gradient at drag start,
    /// every event recomputes the new paint from it plus the cursor.
    private struct GradientDragState {
        enum Kind {
            case start  // linear p0 / radial centre
            case end  // linear p1 / radial radius handle
            case stop(Int)  // stop chip (index into the FULL stops array)
        }
        var shapeID: Int
        var kind: Kind
        var paint: PaintValue
    }

    /// Endpoint drags snap like anchors (point snap wins, then grid); stop
    /// chips project the cursor onto the axis and move in offset space.
    private func applyGradientDrag(_ gd: GradientDragState, target: Pt, in size: CGSize) {
        guard var shape = session.document.firstShape(id: gd.shapeID) else { return }
        var paint = gd.paint
        switch (gd.kind, gd.paint) {
        case (.start, .linear(var g)):
            g.p0 = pointOrGridSnapped(target, in: size)
            paint = .linear(g)
        case (.end, .linear(var g)):
            g.p1 = pointOrGridSnapped(target, in: size)
            paint = .linear(g)
        case (.start, .radial(var g)):
            g.center = pointOrGridSnapped(target, in: size)
            paint = .radial(g)
        case (.end, .radial(var g)):
            g.radius = max(0.01, hypot(target.x - g.center.x, target.y - g.center.y))
            paint = .radial(g)
        case (.stop(let index), _):
            guard var stops = gd.paint.gradientStops, stops.indices.contains(index),
                let axis = Self.gradientAxis(gd.paint)
            else { return }
            let dx = axis.1.x - axis.0.x
            let dy = axis.1.y - axis.0.y
            let len2 = dx * dx + dy * dy
            guard len2 > 1e-12 else { return }
            let t = ((target.x - axis.0.x) * dx + (target.y - axis.0.y) * dy) / len2
            stops[index].offset = max(0.01, min(0.99, t))
            paint = gd.paint.withGradientStops(stops)
        default:
            return
        }
        shape.style.fill = paint
        session.updateShapes([shape])
    }

    // MARK: - Distort chrome

    /// Free Distort: the warped quad through the four corners plus a square
    /// handle per corner (the normal selection chrome hides meanwhile).
    private func drawDistortChrome(
        _ d: EditorSession.DistortState, _ ctx: inout GraphicsContext, t: T
    ) {
        func view(_ p: Pt) -> CGPoint {
            CGPoint(x: p.x * t.s + t.tx, y: p.y * t.s + t.ty)
        }
        guard d.corners.count == 4 else { return }
        var quad = Path()
        quad.move(to: view(d.corners[0]))
        for c in d.corners.dropFirst() {
            quad.addLine(to: view(c))
        }
        quad.closeSubpath()
        ctx.stroke(
            quad, with: .color(.fekthorAccent.opacity(0.9)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        for c in d.corners {
            let p = view(c)
            let rect = CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
            ctx.fill(Path(rect), with: .color(.white))
            ctx.stroke(Path(rect), with: .color(.fekthorAccent), lineWidth: 1.5)
        }
    }

    /// SVG default: shapes with no fill declaration fill black — but a
    /// stroke-only icon declaring only stroke properties usually sets
    /// `fill: none` explicitly; when it does not and a stroke exists, we
    /// still honour the spec default (black fill).
    private func defaultFill(for s: ShapeNode) -> PaintValue? {
        if case .line = s.kind { return nil }  // lines cannot fill
        if case .polyline = s.kind { return nil }
        return .color(r: 0, g: 0, b: 0)
    }

    private func color(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> Color {
        Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    private func shapePath(_ s: ShapeNode) -> CGPath {
        let base = CGPathBuilder.path(for: s.kind)
        guard let t = s.transform else { return base }
        let m = t.matrix
        var affine = CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5])
        return base.copy(using: &affine) ?? base
    }

    // MARK: - Transform (document → view)

    private struct T {
        var s: CGFloat
        var tx: CGFloat
        var ty: CGFloat
    }

    private func transform(doc: GraphicDocument, in size: CGSize) -> T {
        let W = CGFloat(doc.viewBox.width)
        let H = CGFloat(doc.viewBox.height)
        guard W > 0, H > 0 else { return T(s: 1, tx: 0, ty: 0) }
        let s0 = min(size.width / W, size.height / H) * 0.9
        let s = s0 * zoom
        let tx = size.width / 2 - s * (CGFloat(doc.viewBox.minX) + W / 2) + offset.width
        let ty = size.height / 2 - s * (CGFloat(doc.viewBox.minY) + H / 2) + offset.height
        return T(s: s, tx: tx, ty: ty)
    }

    private func docPoint(from v: CGPoint, in size: CGSize) -> Pt {
        let t = transform(doc: session.document, in: size)
        return Pt(Double((v.x - t.tx) / t.s), Double((v.y - t.ty) / t.s))
    }

    // MARK: - Selection box geometry

    /// The eight scale handles on the selection frame.
    private enum BoxHandle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        /// Handle position on the unit box.
        var unit: CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: 0, y: 0)
            case .top: return CGPoint(x: 0.5, y: 0)
            case .topRight: return CGPoint(x: 1, y: 0)
            case .right: return CGPoint(x: 1, y: 0.5)
            case .bottomRight: return CGPoint(x: 1, y: 1)
            case .bottom: return CGPoint(x: 0.5, y: 1)
            case .bottomLeft: return CGPoint(x: 0, y: 1)
            case .left: return CGPoint(x: 0, y: 0.5)
            }
        }
        var scalesX: Bool { unit.x != 0.5 }
        var scalesY: Bool { unit.y != 0.5 }
        /// The fixed point of the scale: the opposite corner/edge.
        var anchorUnit: CGPoint { CGPoint(x: 1 - unit.x, y: 1 - unit.y) }
    }

    private struct TransformDrag {
        enum Kind {
            case scale(BoxHandle)
            case rotate
        }
        var kind: Kind
        /// Selected shapes as they were at drag start; every event recomputes
        /// from these so nothing accumulates.
        var originals: [ShapeNode]
        /// Doc-space selection bounds at drag start.
        var box: CGRect
    }

    /// Union of the selected shapes' geometric bounds (doc coordinates).
    private func selectionDocBounds() -> CGRect? {
        var rect: CGRect? = nil
        for id in session.selection {
            guard let shape = session.document.firstShape(id: id),
                let b = Editing2.bounds(of: shape)
            else { continue }
            let r = CGRect(
                x: b.minX, y: b.minY, width: b.maxX - b.minX, height: b.maxY - b.minY)
            rect = rect.map { $0.union(r) } ?? r
        }
        return rect
    }

    private func paddedViewRect(_ box: CGRect, t: T) -> CGRect {
        CGRect(
            x: box.minX * t.s + t.tx, y: box.minY * t.s + t.ty,
            width: box.width * t.s, height: box.height * t.s
        ).insetBy(dx: -boxPad, dy: -boxPad)
    }

    private func handlePoint(_ h: BoxHandle, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * h.unit.x, y: rect.minY + rect.height * h.unit.y)
    }

    private func rotateKnobPoint(for rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.minY - 18)
    }

    private func selectedOriginals() -> [ShapeNode] {
        session.selection.sorted().compactMap { session.document.firstShape(id: $0) }
    }

    // MARK: - Interaction

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !gestureBegan {
                    gestureBegan = true
                    beginDrag(v, in: size)
                }
                continueDrag(v, in: size)
            }
            .onEnded { v in
                endDrag(v, in: size)
            }
    }

    /// Classify the press: distort corner (while Free Distort is live) →
    /// gradient annotator → Bézier handle → anchor → transform handle →
    /// selected body → marquee (Select tool), or a shape-drawing start.
    private func beginDrag(_ v: DragGesture.Value, in size: CGSize) {
        // Free Distort owns the canvas: corner drags only, everything else
        // is inert until Return commits or Esc cancels.
        if let d = session.distort {
            let t = transform(doc: session.document, in: size)
            var best: (Int, CGFloat)? = nil
            for (i, c) in d.corners.enumerated() {
                let cv = CGPoint(x: c.x * t.s + t.tx, y: c.y * t.s + t.ty)
                let dist = hypot(cv.x - v.startLocation.x, cv.y - v.startLocation.y)
                if dist <= hitRadius + 2, best == nil || dist < best!.1 {
                    best = (i, dist)
                }
            }
            distortCorner = best?.0
            // Distort corners snap like anchors: to grid, and to other
            // shapes' points when the magnet toggle is on.
            if distortCorner != nil {
                snapMagnets = collectMagnets(excluding: Set(d.originals.map(\.id)))
            }
            return
        }
        if session.tool == .pen {
            beginPen(v, in: size)
            return
        }
        if session.tool != .select {
            snapMagnets = collectMagnets(excluding: [])
            drawStart = pointOrGridSnapped(docPoint(from: v.startLocation, in: size), in: size)
            return
        }
        let doc = session.document
        let t = transform(doc: doc, in: size)
        // Gradient annotator (single selection with a gradient fill): stop
        // chips first — they ride the axis — then the endpoint handles.
        if let gh = gradientHandles(t: t) {
            func near(_ p: CGPoint) -> Bool {
                hypot(p.x - v.startLocation.x, p.y - v.startLocation.y) <= hitRadius - 1
            }
            if let chip = gh.stops.first(where: { near($0.point) }) {
                session.beginGesture(label: "Gradient stop")
                gradientDrag = GradientDragState(
                    shapeID: gh.shapeID, kind: .stop(chip.index), paint: gh.paint)
                return
            }
            if near(gh.a) {
                session.beginGesture(label: gh.isRadial ? "Gradient centre" : "Gradient axis")
                gradientDrag = GradientDragState(
                    shapeID: gh.shapeID, kind: .start, paint: gh.paint)
                return
            }
            if near(gh.b) {
                session.beginGesture(label: gh.isRadial ? "Gradient radius" : "Gradient axis")
                gradientDrag = GradientDragState(
                    shapeID: gh.shapeID, kind: .end, paint: gh.paint)
                return
            }
        }
        // Corner dots (single selection): smaller hit radius than anchors —
        // the dot sits 11pt off the anchor, so the two never fight.
        if let sel = single, let shape = doc.firstShape(id: sel), session.distort == nil {
            var best: (path: Int, info: LiveCorners.CornerInfo, d: CGFloat)? = nil
            for (pi, info, dot) in cornerDots(of: shape, t: t) {
                let d = hypot(dot.x - v.startLocation.x, dot.y - v.startLocation.y)
                if d <= hitRadius - 2, best == nil || d < best!.d {
                    best = (pi, info, d)
                }
            }
            if let hit = best {
                session.beginGesture(label: "Corner radius")
                // Selection rule: a selected POINT scopes the edit to the
                // dragged corner; a plain shape selection rounds them all.
                cornerDrag = CornerDrag(
                    originals: selectedOriginals(),
                    path: hit.path, index: hit.info.index,
                    anchor: hit.info.position, bisector: hit.info.bisector,
                    only: activeAnchor != nil ? [hit.path: [hit.info.index]] : nil)
                return
            }
        }
        if let sel = single, let shape = doc.firstShape(id: sel) {
            if let active = activeAnchor {
                for h in Editing2.handles(of: shape, path: active.path, anchor: active.index) {
                    let hv = CGPoint(
                        x: h.position.x * t.s + t.tx, y: h.position.y * t.s + t.ty)
                    if hypot(hv.x - v.startLocation.x, hv.y - v.startLocation.y) <= hitRadius {
                        session.beginGesture(label: "Move handle")
                        draggingHandle = (h.segment, h.kind)
                        return
                    }
                }
            }
            var best: (Editing2.Anchor, CGFloat)? = nil
            for a in Editing2.anchors(of: shape) {
                let av = CGPoint(
                    x: a.position.x * t.s + t.tx, y: a.position.y * t.s + t.ty)
                let d = hypot(av.x - v.startLocation.x, av.y - v.startLocation.y)
                if d <= hitRadius, best == nil || d < best!.1 {
                    best = (a, d)
                }
            }
            if let hit = best {
                session.beginGesture(label: "Move anchor")
                snapMagnets = collectMagnets(excluding: session.selection)
                draggingAnchor = (hit.0.path, hit.0.index)
                activeAnchor = (hit.0.path, hit.0.index)
                return
            }
        }
        // Transform handles on the selection frame (any selection size).
        if !session.selection.isEmpty, let box = selectionDocBounds() {
            let view = paddedViewRect(box, t: t)
            let knob = rotateKnobPoint(for: view)
            if hypot(knob.x - v.startLocation.x, knob.y - v.startLocation.y) <= hitRadius - 1 {
                session.beginGesture(label: "Rotate")
                transformDrag = TransformDrag(kind: .rotate, originals: selectedOriginals(), box: box)
                return
            }
            for h in BoxHandle.allCases {
                let p = handlePoint(h, in: view)
                if hypot(p.x - v.startLocation.x, p.y - v.startLocation.y) <= hitRadius - 1 {
                    session.beginGesture(label: "Scale")
                    // Scale drags snap the dragged handle to grid/points,
                    // same rules as anchor drags (⌃ bypasses).
                    snapMagnets = collectMagnets(excluding: session.selection)
                    transformDrag = TransformDrag(
                        kind: .scale(h), originals: selectedOriginals(), box: box)
                    return
                }
            }
        }
        // Body drag / marquee. ⌘-presses keep their click meanings
        // (add-anchor, toggle-select) — no drag starts on them.
        guard !NSEvent.modifierFlags.contains(.command) else { return }
        let hit = hitNode(at: v.startLocation, in: size)
        if let hit, session.selection.contains(hit) {
            session.beginGesture(label: "Move")
            snapMagnets = collectMagnets(excluding: session.selection)
            draggingBody = true
            moveOrigin = docPoint(from: v.startLocation, in: size)
            moveApplied = Pt(0, 0)
            return
        }
        if hit == nil {
            marqueeBase = NSEvent.modifierFlags.contains(.shift) ? session.selection : []
            marqueeRect = CGRect(origin: v.startLocation, size: .zero)
        }
    }

    private func continueDrag(_ v: DragGesture.Value, in size: CGSize) {
        if session.distort != nil {
            if let corner = distortCorner {
                session.distortDrag(
                    corner: corner,
                    to: pointOrGridSnapped(docPoint(from: v.location, in: size), in: size))
            }
            return
        }
        if session.tool == .pen {
            continuePen(v, in: size)
            return
        }
        if session.tool != .select {
            updateDraft(v, in: size)
            return
        }
        let target = docPoint(from: v.location, in: size)
        if let gd = gradientDrag {
            applyGradientDrag(gd, target: target, in: size)
            return
        }
        if let cd = cornerDrag {
            applyCornerDrag(cd, target: target, in: size)
            return
        }
        if let drag = transformDrag {
            let start = docPoint(from: v.startLocation, in: size)
            switch drag.kind {
            case .scale(let h):
                applyScale(drag, handle: h, start: start, target: target, in: size)
            case .rotate: applyRotate(drag, start: start, target: target)
            }
        } else if let h = draggingHandle, let sel = single, let active = activeAnchor {
            let mirror = !NSEvent.modifierFlags.contains(.option)
            // Handles drag free by default; ⇧ snaps them to the grid too
            // (even when the global snap toggle is off).
            let want =
                NSEvent.modifierFlags.contains(.shift) ? forceSnapped(target) : target
            session.moveHandle(
                node: sel, path: active.path, segment: h.segment, kind: h.kind,
                to: want, mirror: mirror)
        } else if let d = draggingAnchor, let sel = single {
            session.moveAnchor(
                node: sel, path: d.path, anchor: d.index,
                to: pointOrGridSnapped(target, in: size))
        } else if draggingBody, let origin = moveOrigin {
            // Point snap sticks the GRAB POINT to the magnet (the shape
            // keeps its offset to the cursor); grid snap keeps quantising
            // the cumulative delta as before.
            let want: Pt
            if let m = magnetNear(target, in: size) {
                activeMagnet = m
                want = Pt(m.x - origin.x, m.y - origin.y)
            } else {
                activeMagnet = nil
                let raw = Pt(target.x - origin.x, target.y - origin.y)
                if let step = snapStep {
                    want = Pt((raw.x / step).rounded() * step, (raw.y / step).rounded() * step)
                } else {
                    want = raw
                }
            }
            session.translateSelection(dx: want.x - moveApplied.x, dy: want.y - moveApplied.y)
            moveApplied = want
        } else if marqueeRect != nil {
            marqueeRect = CGRect(
                x: min(v.startLocation.x, v.location.x),
                y: min(v.startLocation.y, v.location.y),
                width: abs(v.location.x - v.startLocation.x),
                height: abs(v.location.y - v.startLocation.y))
        }
    }

    private func endDrag(_ v: DragGesture.Value, in size: CGSize) {
        defer {
            gestureBegan = false
            snapMagnets = []
            activeMagnet = nil
        }
        if session.distort != nil {
            distortCorner = nil
            return
        }
        if session.tool == .pen {
            endPen(v, in: size)
            return
        }
        if session.tool != .select {
            finishDraft(v, in: size)
            return
        }
        if gradientDrag != nil {
            gradientDrag = nil
            return
        }
        if cornerDrag != nil {
            cornerDrag = nil
            return
        }
        if transformDrag != nil {
            transformDrag = nil
            return
        }
        if let band = marqueeRect {
            marqueeRect = nil
            applyMarquee(band, in: size)
            return
        }
        let wasEditing = draggingAnchor != nil || draggingHandle != nil || draggingBody
        draggingAnchor = nil
        draggingHandle = nil
        draggingBody = false
        moveOrigin = nil
        guard !wasEditing else { return }
        // Click: select.
        let shift = NSEvent.modifierFlags.contains(.shift)
        let cmd = NSEvent.modifierFlags.contains(.command)
        // ⌘-click near a SELECTED shape's outline (not on an anchor
        // or handle): add a point there and make it the active anchor.
        if cmd, !shift, let ins = insertionCandidate(at: v.location, in: size) {
            session.insertAnchor(
                node: ins.node, path: ins.path, segment: ins.segment, t: ins.t)
            session.selection = [ins.node]
            activeAnchor = (ins.path, ins.anchorIndex)
            return
        }
        if let hit = hitNode(at: v.location, in: size) {
            if shift || cmd {
                if session.selection.contains(hit) {
                    session.selection.remove(hit)
                } else {
                    session.selection.insert(hit)
                }
                activeAnchor = nil
            } else {
                session.selection = [hit]
                activeAnchor = nil
            }
        } else if !shift && !cmd {
            session.selection = []
            activeAnchor = nil
        }
        session.generation += 1
    }

    // MARK: - Corner-dot drag (live corner radius)

    /// Drag distance along the corner's bisector = radius: every event
    /// re-fillets the ORIGINAL geometry with the new radius (dragging back
    /// to the dot restores the sharp corner). Grid snap quantises the
    /// radius so rounded corners land on grid-friendly values.
    private func applyCornerDrag(_ cd: CornerDrag, target: Pt, in size: CGSize) {
        let t = transform(doc: session.document, in: size)
        let baseOffset = Double(cornerDotOffset / t.s)
        let proj =
            (target.x - cd.anchor.x) * cd.bisector.x + (target.y - cd.anchor.y) * cd.bisector.y
        var radius = max(0, proj - baseOffset)
        if let step = snapStep {
            radius = (radius / step).rounded() * step
        }
        session.updateShapes(
            cd.originals.map {
                EditorSession.roundedShape($0, radius: radius, corners: cd.only)
            })
        session.status = String(
            format: cd.only == nil ? "Corner radius %.1f (all corners)" : "Corner radius %.1f",
            radius)
    }

    // MARK: - Scale / rotate application

    /// Scale relative to the grab point so the geometry tracks the pointer
    /// exactly (the frame is padded, so the theoretical handle position
    /// would introduce a jump). ⇧ locks aspect, ⌥ scales from the centre.
    /// The dragged handle snaps to grid/points like an anchor (⌃ bypasses).
    private func applyScale(
        _ drag: TransformDrag, handle: BoxHandle, start: Pt, target rawTarget: Pt,
        in size: CGSize
    ) {
        let target = pointOrGridSnapped(rawTarget, in: size)
        let box = drag.box
        let option = NSEvent.modifierFlags.contains(.option)
        let shift = NSEvent.modifierFlags.contains(.shift)
        let anchorUnit = option ? CGPoint(x: 0.5, y: 0.5) : handle.anchorUnit
        let a = Pt(
            Double(box.minX) + Double(box.width) * Double(anchorUnit.x),
            Double(box.minY) + Double(box.height) * Double(anchorUnit.y))
        var sx = 1.0
        var sy = 1.0
        if handle.scalesX, abs(start.x - a.x) > 1e-9 { sx = (target.x - a.x) / (start.x - a.x) }
        if handle.scalesY, abs(start.y - a.y) > 1e-9 { sy = (target.y - a.y) / (start.y - a.y) }
        if shift {
            let s: Double
            if handle.scalesX && handle.scalesY {
                s = abs(sx) > abs(sy) ? sx : sy
            } else {
                s = handle.scalesX ? sx : sy
            }
            sx = s
            sy = s
        }
        // Never collapse to zero mid-drag (degenerate geometry is sticky).
        if abs(sx) < 0.005 { sx = sx < 0 ? -0.005 : 0.005 }
        if abs(sy) < 0.005 { sy = sy < 0 ? -0.005 : 0.005 }
        let fx = sx
        let fy = sy
        session.updateShapes(drag.originals.map { Editing2.scaled($0, sx: fx, sy: fy, around: a) })
        session.status = String(
            format: "%.1f × %.1f", Double(box.width) * abs(sx), Double(box.height) * abs(sy))
    }

    /// Rotate around the selection centre; ⇧ snaps to 15° steps.
    private func applyRotate(_ drag: TransformDrag, start: Pt, target: Pt) {
        let c = Pt(Double(drag.box.midX), Double(drag.box.midY))
        var angle = atan2(target.y - c.y, target.x - c.x) - atan2(start.y - c.y, start.x - c.x)
        if NSEvent.modifierFlags.contains(.shift) {
            let step = Double.pi / 12  // 15°
            angle = (angle / step).rounded() * step
        }
        session.updateShapes(drag.originals.map { Editing2.rotated($0, by: angle, around: c) })
        var deg = angle * 180 / .pi
        while deg > 180 { deg -= 360 }
        while deg <= -180 { deg += 360 }
        session.status = String(format: "%.1f°", deg)
    }

    // MARK: - Marquee

    /// Select every shape whose bounds intersect the band; ⇧ adds to the
    /// pre-marquee selection. A tiny band is an empty-space click: deselect.
    private func applyMarquee(_ band: CGRect, in size: CGSize) {
        defer { session.generation += 1 }
        if band.width < 4, band.height < 4 {
            if !NSEvent.modifierFlags.contains(.shift) {
                session.selection = []
                activeAnchor = nil
            }
            return
        }
        let t = transform(doc: session.document, in: size)
        let docRect = CGRect(
            x: (band.minX - t.tx) / t.s, y: (band.minY - t.ty) / t.s,
            width: band.width / t.s, height: band.height / t.s)
        var picked = marqueeBase
        func walk(_ nodes: [GraphicNode]) {
            for node in nodes {
                switch node {
                case .raw: continue
                case .group(let g):
                    guard !g.renderStyle.isDisplayNone,
                        !session.lockedNodes.contains(g.id)
                    else { continue }
                    walk(g.children)
                case .shape(let s):
                    guard !s.renderStyle.isDisplayNone,
                        !session.lockedNodes.contains(s.id)
                    else { continue }
                    guard let b = Editing2.bounds(of: s) else { continue }
                    let r = CGRect(
                        x: b.minX, y: b.minY, width: b.maxX - b.minX, height: b.maxY - b.minY)
                    if r.intersects(docRect) { picked.insert(s.id) }
                }
            }
        }
        walk(session.document.nodes)
        session.selection = picked
        activeAnchor = nil
    }

    // MARK: - Shape drawing

    private func updateDraft(_ v: DragGesture.Value, in size: CGSize) {
        guard let start = drawStart else { return }
        let cur = pointOrGridSnapped(docPoint(from: v.location, in: size), in: size)
        let flags = NSEvent.modifierFlags
        drawDraft = draftKind(
            from: start, to: cur, shift: flags.contains(.shift),
            option: flags.contains(.option))
        if let draft = drawDraft, let b = Editing2.bounds(of: ShapeNode(id: -1, kind: draft)) {
            session.status = String(format: "%.1f × %.1f", b.maxX - b.minX, b.maxY - b.minY)
        }
    }

    private func finishDraft(_ v: DragGesture.Value, in size: CGSize) {
        defer {
            drawStart = nil
            drawDraft = nil
        }
        let dist = hypot(
            v.location.x - v.startLocation.x, v.location.y - v.startLocation.y)
        guard dist >= 3, let kind = drawDraft else { return }
        session.insertShape(kind: kind)
    }

    /// The primitive being dragged out. ⇧ constrains (square / circle / 45°
    /// line), ⌥ draws from the centre. A ⇧-constrained ellipse inserts a
    /// native `.circle`.
    private func draftKind(from s: Pt, to p: Pt, shift: Bool, option: Bool) -> ShapeKind? {
        var d = Pt(p.x - s.x, p.y - s.y)
        switch session.tool {
        case .select, .pen:
            return nil  // pen paths are built anchor by anchor, not dragged out
        case .line:
            if shift {
                let len = (d.x * d.x + d.y * d.y).squareRoot()
                if len > 1e-9 {
                    let step = Double.pi / 4
                    let angle = (atan2(d.y, d.x) / step).rounded() * step
                    d = Pt(len * cos(angle), len * sin(angle))
                }
            }
            let a = option ? Pt(s.x - d.x, s.y - d.y) : s
            let b = Pt(s.x + d.x, s.y + d.y)
            guard a != b else { return nil }
            return .line(a, b)
        case .rect, .ellipse:
            if shift {
                let m = max(abs(d.x), abs(d.y))
                d = Pt(d.x < 0 ? -m : m, d.y < 0 ? -m : m)
            }
            let w = option ? abs(d.x) * 2 : abs(d.x)
            let h = option ? abs(d.y) * 2 : abs(d.y)
            guard w > 1e-6, h > 1e-6 else { return nil }
            let x0 = option ? s.x - w / 2 : min(s.x, s.x + d.x)
            let y0 = option ? s.y - h / 2 : min(s.y, s.y + d.y)
            if session.tool == .rect {
                return .rect(x: x0, y: y0, width: w, height: h, rx: nil, ry: nil)
            }
            let c = Pt(x0 + w / 2, y0 + h / 2)
            if abs(w - h) < 1e-9 {
                return .circle(center: c, r: w / 2)
            }
            return .ellipse(center: c, rx: w / 2, ry: h / 2)
        }
    }

    // MARK: - Pen tool

    /// Pen press. On the FIRST anchor (with ≥2 placed) it closes the path;
    /// anywhere else it places the next anchor (snapped) — a corner until
    /// the drag pulls handles out.
    private func beginPen(_ v: DragGesture.Value, in size: CGSize) {
        // The double-click finish (TrackpadCatcher monitor) fires on the
        // second mouse-down BEFORE this gesture sees it — that second click
        // must not seed a stray new path.
        if let e = NSApp.currentEvent, e.type == .leftMouseDown, e.clickCount >= 2 {
            return
        }
        let t = transform(doc: session.document, in: size)
        session.penTolerance = Double(hitRadius / t.s)
        penDragging = false
        if penCloseHit(v.startLocation, t: t) {
            penClosing = true
            return
        }
        penClosing = false
        snapMagnets = collectMagnets(excluding: [])
        session.penAppendAnchor(
            at: pointOrGridSnapped(docPoint(from: v.startLocation, in: size), in: size))
    }

    /// Dragging pulls the newest anchor's outgoing handle to the cursor
    /// (unsnapped — snap is for anchors); the incoming handle mirrors it
    /// unless ⌥ breaks the symmetry.
    private func continuePen(_ v: DragGesture.Value, in size: CGSize) {
        penHover = v.location
        guard !penClosing else { return }
        if !penDragging {
            let dist = hypot(
                v.location.x - v.startLocation.x, v.location.y - v.startLocation.y)
            guard dist > 3 else { return }
            penDragging = true
        }
        let out = docPoint(from: v.location, in: size)
        session.penSetLastHandles(out: out, mirror: !NSEvent.modifierFlags.contains(.option))
    }

    private func endPen(_ v: DragGesture.Value, in size: CGSize) {
        defer {
            penDragging = false
            penClosing = false
        }
        if penClosing {
            session.finishPenPath(closed: true)
        }
    }

    /// Is a view point on the first pen anchor (the close target)?
    private func penCloseHit(_ p: CGPoint, t: T) -> Bool {
        guard session.penAnchors.count >= 2, let first = session.penAnchors.first
        else { return false }
        let fv = CGPoint(x: first.point.x * t.s + t.tx, y: first.point.y * t.s + t.ty)
        return hypot(fv.x - p.x, fv.y - p.y) <= hitRadius
    }

    /// The in-progress pen path: committed segments in the current drawing
    /// style, a rubber band from the newest anchor to the cursor, the
    /// newest anchor's handle levers while they exist, anchor dots, and a
    /// close badge when the cursor is over the first anchor.
    private func drawPenPreview(_ ctx: inout GraphicsContext, base: CGAffineTransform, t: T) {
        let anchors = session.penAnchors
        guard let last = anchors.last, let first = anchors.first else { return }
        func view(_ p: Pt) -> CGPoint {
            CGPoint(x: p.x * t.s + t.tx, y: p.y * t.s + t.ty)
        }
        // Committed segments, styled like the shape they will become.
        if let path = session.penPreviewPath() {
            let node = ShapeNode(id: -1, kind: .path([path]), style: session.drawingStyle)
            drawNodes([.shape(node)], into: &ctx, base: base, scale: t.s, opacity: 1)
        }
        // Rubber band to the cursor (hover; during a handle drag the levers
        // are the live feedback). Aimed at the close target it previews the
        // closing segment instead.
        let closing = penHover.map { penCloseHit($0, t: t) } ?? false
        if !penDragging, let hover = penHover {
            let target: PenTargetAnchor
            if closing {
                target = PenTargetAnchor(point: first.point, handleIn: first.handleIn)
            } else {
                target = PenTargetAnchor(
                    point: snapped(docPoint(from: hover, in: t)), handleIn: nil)
            }
            let seg: RefinedSegment
            if last.handleOut == nil && target.handleIn == nil {
                seg = .line(to: target.point)
            } else {
                seg = .cubic(
                    c1: last.handleOut ?? last.point,
                    c2: target.handleIn ?? target.point, to: target.point)
            }
            let band = RefinedPath(start: last.point, segments: [seg], closed: false)
            var p = Path(CGPathBuilder.path(for: .path([band])))
            p = p.applying(base)
            ctx.stroke(
                p, with: .color(.blue.opacity(0.6)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        // Handle levers on the newest anchor.
        let av = view(last.point)
        for h in [last.handleIn, last.handleOut].compactMap({ $0 }) {
            let hv = view(h)
            var lever = Path()
            lever.move(to: av)
            lever.addLine(to: hv)
            ctx.stroke(lever, with: .color(.blue.opacity(0.6)), lineWidth: 1)
            let r: CGFloat = 3
            ctx.fill(
                Path(
                    ellipseIn: CGRect(x: hv.x - r, y: hv.y - r, width: 2 * r, height: 2 * r)),
                with: .color(.blue))
        }
        // Anchor dots; the first one grows a ring when it is the close target.
        for (i, a) in anchors.enumerated() {
            let p = view(a.point)
            let r: CGFloat = i == anchors.count - 1 ? 4 : 3.5
            let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rect), with: .color(i == 0 ? .blue : .white))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.blue), lineWidth: 1.5)
            if i == 0, closing {
                let ring = rect.insetBy(dx: -3.5, dy: -3.5)
                ctx.stroke(Path(ellipseIn: ring), with: .color(.blue.opacity(0.8)), lineWidth: 1.5)
            }
        }
        // Close badge riding the cursor near the first anchor.
        if closing, let hover = penHover {
            let badge = CGRect(x: hover.x + 9, y: hover.y + 9, width: 7, height: 7)
            ctx.fill(Path(ellipseIn: badge), with: .color(.white))
            ctx.stroke(Path(ellipseIn: badge), with: .color(.blue), lineWidth: 1.2)
        }
    }

    /// A rubber-band target: either the raw cursor or the close anchor.
    private struct PenTargetAnchor {
        var point: Pt
        var handleIn: Pt?
    }

    /// docPoint variant for contexts that already computed the transform.
    private func docPoint(from v: CGPoint, in t: T) -> Pt {
        Pt(Double((v.x - t.tx) / t.s), Double((v.y - t.ty) / t.s))
    }

    // MARK: - Hit testing

    /// ⌘-click "add point" hit test: the closest outline point across the
    /// SELECTED shapes, within ~6pt on screen, and not over an existing
    /// anchor or handle (those clicks keep their select/drag meaning).
    private func insertionCandidate(at point: CGPoint, in size: CGSize)
        -> (node: Int, path: Int, segment: Int, t: Double, anchorIndex: Int)?
    {
        guard !session.selection.isEmpty else { return nil }
        let doc = session.document
        let t = transform(doc: doc, in: size)
        for id in session.selection {
            guard let shape = doc.firstShape(id: id) else { continue }
            for a in Editing2.anchors(of: shape) {
                let av = CGPoint(x: a.position.x * t.s + t.tx, y: a.position.y * t.s + t.ty)
                if hypot(av.x - point.x, av.y - point.y) <= hitRadius { return nil }
            }
        }
        if let sel = single, let shape = doc.firstShape(id: sel), let active = activeAnchor {
            for h in Editing2.handles(of: shape, path: active.path, anchor: active.index) {
                let hv = CGPoint(x: h.position.x * t.s + t.tx, y: h.position.y * t.s + t.ty)
                if hypot(hv.x - point.x, hv.y - point.y) <= hitRadius { return nil }
            }
        }
        let dp = docPoint(from: point, in: size)
        let tol = 6.0 / Double(t.s)
        var best: (node: Int, path: Int, segment: Int, t: Double, distance: Double)? = nil
        for id in session.selection.sorted() {
            guard let shape = doc.firstShape(id: id),
                let hit = Editing2.closestPoint(of: shape, to: dp), hit.distance <= tol
            else { continue }
            if best == nil || hit.distance < best!.distance {
                best = (id, hit.path, hit.segment, hit.t, hit.distance)
            }
        }
        return best.map {
            (node: $0.node, path: $0.path, segment: $0.segment, t: $0.t,
                anchorIndex: $0.segment + 1)
        }
    }

    /// Topmost shape under a view point (fills by containment, stroked
    /// shapes by distance to the outline).
    private func hitNode(at point: CGPoint, in size: CGSize) -> Int? {
        let doc = session.document
        let t = transform(doc: doc, in: size)
        let dp = docPoint(from: point, in: size)
        let cgPoint = CGPoint(x: dp.x, y: dp.y)
        var hit: Int? = nil
        func walk(_ nodes: [GraphicNode]) {
            for node in nodes {
                switch node {
                case .raw: continue
                case .group(let g):
                    // Hidden or locked groups are untouchable, subtree
                    // included (Layers palette semantics).
                    guard !g.renderStyle.isDisplayNone,
                        !session.lockedNodes.contains(g.id)
                    else { continue }
                    walk(g.children)
                case .shape(let s):
                    let style = s.renderStyle
                    guard !style.isDisplayNone, !session.lockedNodes.contains(s.id)
                    else { continue }
                    let path = shapePath(s)
                    let hasFill: Bool
                    if let f = style.fill {
                        hasFill = f != PaintValue.none
                    } else {
                        hasFill = defaultFill(for: s) != nil
                    }
                    if hasFill, path.contains(cgPoint, using: .evenOdd) {
                        hit = s.id
                        continue
                    }
                    let width = max(style.strokeWidth ?? 1, 8 / Double(t.s))
                    // Zero-length lines (dots) produce an empty stroked
                    // copy; hit-test the cap disc directly.
                    if case .line(let a, let b) = s.kind, a.x == b.x, a.y == b.y {
                        if hypot(a.x - dp.x, a.y - dp.y) <= width / 2 { hit = s.id }
                        continue
                    }
                    let stroked = path.copy(
                        strokingWithWidth: width, lineCap: .round, lineJoin: .round,
                        miterLimit: 10)
                    if stroked.contains(cgPoint) {
                        hit = s.id
                    }
                }
            }
        }
        walk(doc.nodes)
        return hit
    }

    // MARK: - Context menu

    // MARK: - Tool cursors

    /// One cursor per canvas tool: arrow for Select (the transform handles'
    /// feedback stays drawn chrome), crosshair for the drag-out shape tools,
    /// and a pen nib for the pen. All cursors are built once and cached.
    private enum ToolCursors {
        static func cursor(for tool: EditorSession.Tool) -> NSCursor {
            switch tool {
            case .select: return .arrow
            case .rect, .ellipse, .line: return .crosshair
            case .pen: return pen
            }
        }

        /// A pen cursor from the `pencil.tip` SF Symbol (the tool button's
        /// own glyph): black nib over a white halo so it reads on any canvas
        /// colour, hotspot on the nib's tip (bottom centre).
        static let pen: NSCursor = {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            guard
                let symbol = NSImage(
                    systemSymbolName: "pencil.tip", accessibilityDescription: "Pen"
                )?.withSymbolConfiguration(config)
            else { return .crosshair }
            let glyph = symbol.size
            let canvas = NSSize(width: glyph.width + 4, height: glyph.height + 4)
            let origin = NSPoint(
                x: (canvas.width - glyph.width) / 2, y: (canvas.height - glyph.height) / 2)
            let dark = tinted(symbol, .black)
            let light = tinted(symbol, .white)
            let image = NSImage(size: canvas, flipped: false) { _ in
                for dx: CGFloat in [-1, 0, 1] {
                    for dy: CGFloat in [-1, 0, 1] where dx != 0 || dy != 0 {
                        light.draw(
                            in: NSRect(
                                origin: NSPoint(x: origin.x + dx, y: origin.y + dy),
                                size: glyph))
                    }
                }
                dark.draw(in: NSRect(origin: origin, size: glyph))
                return true
            }
            // Hotspot in top-left image coordinates: the glyph's bottom
            // centre, one halo pixel in.
            let hotSpot = NSPoint(
                x: canvas.width / 2, y: min(canvas.height - 1, origin.y + glyph.height + 1))
            return NSCursor(image: image, hotSpot: hotSpot)
        }()

        private static func tinted(_ symbol: NSImage, _ color: NSColor) -> NSImage {
            NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
    }

    private func menuItems(at point: CGPoint, in size: CGSize) -> [(String, () -> Void)] {
        var items: [(String, () -> Void)] = []
        if let sel = single, let shape = session.document.firstShape(id: sel) {
            let t = transform(doc: session.document, in: size)
            var best: (Editing2.Anchor, CGFloat)? = nil
            for a in Editing2.anchors(of: shape) {
                let av = CGPoint(x: a.position.x * t.s + t.tx, y: a.position.y * t.s + t.ty)
                let d = hypot(av.x - point.x, av.y - point.y)
                if d <= hitRadius + 3, best == nil || d < best!.1 { best = (a, d) }
            }
            if let (anchor, _) = best {
                items.append((
                    "Remove Point",
                    {
                        session.removeAnchor(node: sel, path: anchor.path, anchor: anchor.index)
                        activeAnchor = nil
                    }
                ))
            }
        }
        // "Add Crossing Points" on the clicked shape, only when its outline
        // actually crosses another visible shape's (checked lazily here, on
        // menu build, for the clicked shape only).
        if let hit = hitNode(at: point, in: size), session.crossingCount(node: hit) > 0 {
            items.append((
                "Add Crossing Points",
                {
                    session.selection = [hit]
                    activeAnchor = nil
                    session.addCrossingPoints(node: hit)
                }
            ))
        }
        if !session.selection.isEmpty {
            items.append(("Delete \(session.selection.count) Node(s)", { session.deleteSelection() }))
        }
        return items
    }
}
