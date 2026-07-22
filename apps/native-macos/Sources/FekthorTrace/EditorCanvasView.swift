import FekthorKit
import SwiftUI

/// The editor canvas for an `EditorSession`: renders the GraphicDocument
/// tree (groups with transforms and opacity, primitives, class-resolved
/// styles) and provides the P0 interactions — click/⇧-click selection,
/// anchor and Bézier-handle drags, body drags to move a shape, right-click
/// point removal. Zoom/offset bindings share the app's navigation gestures.
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

    private let hitRadius: CGFloat = 8

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

            // Anchors + handles for a single selection.
            if let sel = single, let shape = doc.firstShape(id: sel) {
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
                    ctx.stroke(
                        p, with: .color(color(c).opacity(nodeOpacity)), style: strokeStyle)
                }
            }
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

    // MARK: - Interaction

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let doc = session.document
                let t = transform(doc: doc, in: size)
                if !gestureBegan {
                    gestureBegan = true
                    if let sel = single, let shape = doc.firstShape(id: sel) {
                        if let active = activeAnchor {
                            for h in Editing2.handles(
                                of: shape, path: active.path, anchor: active.index)
                            {
                                let hv = CGPoint(
                                    x: h.position.x * t.s + t.tx, y: h.position.y * t.s + t.ty)
                                if hypot(hv.x - v.startLocation.x, hv.y - v.startLocation.y)
                                    <= hitRadius
                                {
                                    session.beginGesture()
                                    draggingHandle = (h.segment, h.kind)
                                    break
                                }
                            }
                        }
                        if draggingHandle == nil {
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
                            }
                        }
                        // Body drag: press inside the selected shape.
                        if draggingHandle == nil, draggingAnchor == nil,
                            hitNode(at: v.startLocation, in: size) == sel
                        {
                            session.beginGesture()
                            draggingBody = true
                            lastDragPoint = docPoint(from: v.startLocation, in: size)
                        }
                    }
                }
                let target = docPoint(from: v.location, in: size)
                if let h = draggingHandle, let sel = single, let active = activeAnchor {
                    let mirror = !NSEvent.modifierFlags.contains(.option)
                    session.moveHandle(
                        node: sel, path: active.path, segment: h.segment, kind: h.kind,
                        to: target, mirror: mirror)
                } else if let d = draggingAnchor, let sel = single {
                    session.moveAnchor(node: sel, path: d.path, anchor: d.index, to: target)
                } else if draggingBody, let last = lastDragPoint {
                    session.translateSelection(dx: target.x - last.x, dy: target.y - last.y)
                    lastDragPoint = target
                }
            }
            .onEnded { v in
                let wasEditing = draggingAnchor != nil || draggingHandle != nil || draggingBody
                draggingAnchor = nil
                draggingHandle = nil
                draggingBody = false
                lastDragPoint = nil
                gestureBegan = false
                guard !wasEditing else { return }
                // Click: select.
                let shift = NSEvent.modifierFlags.contains(.shift)
                let cmd = NSEvent.modifierFlags.contains(.command)
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
