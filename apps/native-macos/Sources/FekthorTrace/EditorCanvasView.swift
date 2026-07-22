import FekthorKit
import SwiftUI

/// The editor canvas for an `EditorSession`: renders the GraphicDocument
/// tree (groups with transforms and opacity, primitives, class-resolved
/// styles) and provides the editing interactions — click/⇧-click selection,
/// marquee, anchor and Bézier-handle drags, body drags to move, selection
/// transform handles (scale + rotate lollipop), shape-drawing tools, and
/// right-click point removal. Zoom/offset bindings share the app's
/// navigation gestures.
struct EditorCanvasView: View {
    @ObservedObject var session: EditorSession
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize

    @State private var activeAnchor: (path: Int, index: Int)? = nil
    @State private var draggingAnchor: (path: Int, index: Int)? = nil
    @State private var draggingHandle: (segment: Int, kind: Editing.HandleKind)? = nil
    @State private var draggingBody = false
    @State private var lastDragPoint: Pt? = nil
    @State private var gestureBegan = false
    @State private var transformDrag: TransformDrag? = nil
    @State private var marqueeRect: CGRect? = nil
    @State private var marqueeBase: Set<Int> = []
    @State private var drawStart: Pt? = nil
    @State private var drawDraft: ShapeKind? = nil

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
        }
        .frame(minWidth: 300, minHeight: 340)
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
            drawSelectionChrome(&ctx, t: t)

            // Shape-tool preview.
            if let draft = drawDraft {
                var p = Path(CGPathBuilder.path(for: draft))
                p = p.applying(cg)
                ctx.stroke(p, with: .color(.blue.opacity(0.8)), lineWidth: 1.5)
            }

            // Marquee band (view coordinates).
            if let band = marqueeRect {
                ctx.fill(Path(band), with: .color(.blue.opacity(0.08)))
                ctx.stroke(Path(band), with: .color(.blue.opacity(0.6)), lineWidth: 1)
            }
        }
        .gesture(dragGesture(in: size))
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
                var groupBase = base
                if let t = g.transform {
                    let m = t.matrix
                    groupBase =
                        CGAffineTransform(
                            a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5]
                        ).concatenating(base)
                }
                let groupOpacity = opacity * (g.style.opacity ?? 1)
                drawNodes(
                    g.children, into: &ctx, base: groupBase, scale: scale,
                    opacity: groupOpacity)
            case .shape(let s):
                var shapeBase = base
                if let t = s.transform {
                    let m = t.matrix
                    shapeBase =
                        CGAffineTransform(
                            a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5]
                        ).concatenating(base)
                }
                let style = s.effectiveStyle
                let nodeOpacity = opacity * (style.opacity ?? 1)
                var p = Path(CGPathBuilder.path(for: s.kind))
                p = p.applying(shapeBase)

                if let fill = style.fill ?? defaultFill(for: s), let c = fill.renderColor {
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
                    ctx.fill(
                        p,
                        with: .color(
                            color(c).opacity(nodeOpacity * fillOpacity)), style: rule)
                }
                if let stroke = style.stroke, let c = stroke.renderColor {
                    let width = style.strokeWidth ?? 1
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
                    ctx.stroke(
                        p, with: .color(color(c).opacity(nodeOpacity)), style: strokeStyle)
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

    /// The selection transform frame: dashed bounding box (padded outward so
    /// its handles clear the shape's own anchors), 8 scale handles, and a
    /// rotate lollipop above the top edge.
    private func drawSelectionChrome(_ ctx: inout GraphicsContext, t: T) {
        guard session.tool == .select, !session.selection.isEmpty,
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

    /// Classify the press: Bézier handle → anchor → transform handle →
    /// selected body → marquee (Select tool), or a shape-drawing start.
    private func beginDrag(_ v: DragGesture.Value, in size: CGSize) {
        if session.tool != .select {
            drawStart = docPoint(from: v.startLocation, in: size)
            return
        }
        let doc = session.document
        let t = transform(doc: doc, in: size)
        if let sel = single, let shape = doc.firstShape(id: sel) {
            if let active = activeAnchor {
                for h in Editing2.handles(of: shape, path: active.path, anchor: active.index) {
                    let hv = CGPoint(
                        x: h.position.x * t.s + t.tx, y: h.position.y * t.s + t.ty)
                    if hypot(hv.x - v.startLocation.x, hv.y - v.startLocation.y) <= hitRadius {
                        session.beginGesture()
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
                session.beginGesture()
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
                session.beginGesture()
                transformDrag = TransformDrag(kind: .rotate, originals: selectedOriginals(), box: box)
                return
            }
            for h in BoxHandle.allCases {
                let p = handlePoint(h, in: view)
                if hypot(p.x - v.startLocation.x, p.y - v.startLocation.y) <= hitRadius - 1 {
                    session.beginGesture()
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
            session.beginGesture()
            draggingBody = true
            lastDragPoint = docPoint(from: v.startLocation, in: size)
            return
        }
        if hit == nil {
            marqueeBase = NSEvent.modifierFlags.contains(.shift) ? session.selection : []
            marqueeRect = CGRect(origin: v.startLocation, size: .zero)
        }
    }

    private func continueDrag(_ v: DragGesture.Value, in size: CGSize) {
        if session.tool != .select {
            updateDraft(v, in: size)
            return
        }
        let target = docPoint(from: v.location, in: size)
        if let drag = transformDrag {
            let start = docPoint(from: v.startLocation, in: size)
            switch drag.kind {
            case .scale(let h): applyScale(drag, handle: h, start: start, target: target)
            case .rotate: applyRotate(drag, start: start, target: target)
            }
        } else if let h = draggingHandle, let sel = single, let active = activeAnchor {
            let mirror = !NSEvent.modifierFlags.contains(.option)
            session.moveHandle(
                node: sel, path: active.path, segment: h.segment, kind: h.kind,
                to: target, mirror: mirror)
        } else if let d = draggingAnchor, let sel = single {
            session.moveAnchor(node: sel, path: d.path, anchor: d.index, to: target)
        } else if draggingBody, let last = lastDragPoint {
            session.translateSelection(dx: target.x - last.x, dy: target.y - last.y)
            lastDragPoint = target
        } else if marqueeRect != nil {
            marqueeRect = CGRect(
                x: min(v.startLocation.x, v.location.x),
                y: min(v.startLocation.y, v.location.y),
                width: abs(v.location.x - v.startLocation.x),
                height: abs(v.location.y - v.startLocation.y))
        }
    }

    private func endDrag(_ v: DragGesture.Value, in size: CGSize) {
        defer { gestureBegan = false }
        if session.tool != .select {
            finishDraft(v, in: size)
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
        lastDragPoint = nil
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

    // MARK: - Scale / rotate application

    /// Scale relative to the grab point so the geometry tracks the pointer
    /// exactly (the frame is padded, so the theoretical handle position
    /// would introduce a jump). ⇧ locks aspect, ⌥ scales from the centre.
    private func applyScale(_ drag: TransformDrag, handle: BoxHandle, start: Pt, target: Pt) {
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
                case .group(let g): walk(g.children)
                case .shape(let s):
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
        let cur = docPoint(from: v.location, in: size)
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
        case .select:
            return nil
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
                    walk(g.children)
                case .shape(let s):
                    let path = shapePath(s)
                    let style = s.effectiveStyle
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
        if !session.selection.isEmpty {
            items.append(("Delete \(session.selection.count) Node(s)", { session.deleteSelection() }))
        }
        return items
    }
}
