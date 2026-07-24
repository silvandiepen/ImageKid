import FekthorKit
import SwiftUI

/// The live vector layer: the document drawn as CGPaths, always editable.
/// Click a shape to select it, drag its anchors or Bézier control levers to
/// reshape — in any view mode, at any zoom. Geometry rules live engine-side
/// in `Editing`; this layer only maps screen ↔ document space.
struct VectorEditLayer: View {
    @ObservedObject var model: ConversionModel
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize
    var busy: Bool = false
    /// Dims only the DRAWN GEOMETRY (overlay mode); anchors and levers always
    /// render at full opacity so editing stays crisp on a faded layer.
    var contentOpacity: Double = 1

    @State private var activeAnchor: (path: Int, index: Int)? = nil
    @State private var multiSel: Set<Editing.AnchorRef> = []
    @State private var draggingAnchor: (path: Int, index: Int)? = nil
    @State private var draggingHandle: (segment: Int, kind: Editing.HandleKind)? = nil
    @State private var gestureBegan = false
    @State private var marquee: CGRect? = nil

    /// Anchor-level editing engages when exactly ONE path is selected.
    private var selected: Int? {
        model.selectedElements.count == 1 ? model.selectedElements.first : nil
    }

    private let hitRadius: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            canvas(in: geo.size)
                .overlay(
                    RightClickCatcher { point, size in
                        menuItems(at: point, in: size)
                    }
                )
        }
    }

    private func canvas(in size: CGSize) -> some View {
        // editGeneration invalidates the canvas on every anchor move.
        let _ = model.editGeneration
        return Canvas { ctx, canvasSize in
            guard let doc = model.document else { return }
            let t = transform(doc: doc, in: canvasSize)
            var cg = CGAffineTransform.identity
            cg = cg.translatedBy(x: t.tx, y: t.ty)
            cg = cg.scaledBy(x: t.s, y: t.s)

            // White artboard behind the document, matching the raster preview.
            let board = CGRect(
                x: t.tx, y: t.ty, width: CGFloat(doc.width) * t.s,
                height: CGFloat(doc.height) * t.s)
            ctx.fill(Path(board), with: .color(.white.opacity(contentOpacity)))

            for element in doc.elements {
                switch element {
                case .fill(let f):
                    let path = CGPathBuilder.fillPath(f.geometry, smoothing: model.smoothing)
                    var p = Path(path)
                    p = p.applying(cg)
                    ctx.fill(
                        p, with: .color(color(f.paint).opacity(contentOpacity)),
                        style: FillStyle(eoFill: true))
                case .stroke(let s):
                    let path = CGPathBuilder.strokePath(s, smoothing: model.smoothing)
                    var p = Path(path)
                    p = p.applying(cg)
                    ctx.stroke(
                        p, with: .color(rgbColor(s.color).opacity(contentOpacity)),
                        style: StrokeStyle(
                            lineWidth: s.width * t.s, lineCap: .round, lineJoin: .round))
                }
            }

            // Selection highlight: every selected path gets a blue outline.
            for i in model.selectedElements.sorted() where i < doc.elements.count {
                let hp: CGPath
                switch doc.elements[i] {
                case .fill(let f):
                    hp = CGPathBuilder.fillPath(f.geometry, smoothing: model.smoothing)
                case .stroke(let st):
                    hp = CGPathBuilder.strokePath(st, smoothing: model.smoothing)
                }
                var p = Path(hp)
                p = p.applying(cg)
                ctx.stroke(p, with: .color(.blue.opacity(0.55)), lineWidth: 2)
            }

            // Marquee rectangle while rubber-band selecting.
            if let m = marquee {
                ctx.stroke(
                    Path(m), with: .color(.blue),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ctx.fill(Path(m), with: .color(.blue.opacity(0.08)))
            }

            // Multi-selected anchors (any element), for break/merge tools.
            for ref in multiSel where ref.element < doc.elements.count {
                let list = Editing.anchors(of: doc.elements[ref.element])
                if let a = list.first(where: { $0.path == ref.path && $0.index == ref.anchor }) {
                    let v = CGPoint(x: a.position.x * t.s + t.tx, y: a.position.y * t.s + t.ty)
                    let r: CGFloat = 5
                    let rect = CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.orange))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
                }
            }

            // Anchors of the selected element; control levers of the active anchor.
            if let sel = selected, sel < doc.elements.count {
                if let active = activeAnchor {
                    for h in Editing.handles(
                        of: doc.elements[sel], path: active.path, anchor: active.index)
                    {
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
                for a in Editing.anchors(of: doc.elements[sel]) {
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
        .opacity(busy ? 0.5 : 1)
        .gesture(
            SpatialTapGesture().modifiers(.shift).onEnded { v in
                toggleMultiSelect(at: v.location, in: size)
            }
        )
        .gesture(dragGesture(in: size))
    }

    // MARK: - Transform (document → view)

    private struct T {
        var s: CGFloat
        var tx: CGFloat
        var ty: CGFloat
    }

    private func transform(doc: VectorDocument, in size: CGSize) -> T {
        let W = CGFloat(doc.width)
        let H = CGFloat(doc.height)
        guard W > 0, H > 0 else { return T(s: 1, tx: 0, ty: 0) }
        let s0 = min(size.width / W, size.height / H)
        let s = s0 * zoom
        // scaledToFit centres the fitted image; scaleEffect scales about the
        // view centre; offset shifts — same maths as the preview panes.
        let tx = size.width / 2 - s * W / 2 + offset.width
        let ty = size.height / 2 - s * H / 2 + offset.height
        return T(s: s, tx: tx, ty: ty)
    }

    private func docPoint(from v: CGPoint, doc: VectorDocument, in size: CGSize) -> Pt {
        let t = transform(doc: doc, in: size)
        return Pt(Double((v.x - t.tx) / t.s), Double((v.y - t.ty) / t.s))
    }

    // MARK: - Interaction

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard let doc = model.document else { return }
                let t = transform(doc: doc, in: size)
                if draggingAnchor == nil, draggingHandle == nil, !gestureBegan {
                    gestureBegan = true
                    // Priority: a control handle of the active anchor, then an
                    // anchor of the selected element; otherwise a selection tap.
                    if let sel = selected, sel < doc.elements.count {
                        if let active = activeAnchor {
                            for h in Editing.handles(
                                of: doc.elements[sel], path: active.path, anchor: active.index)
                            {
                                let hv = CGPoint(
                                    x: h.position.x * t.s + t.tx, y: h.position.y * t.s + t.ty)
                                if hypot(hv.x - v.startLocation.x, hv.y - v.startLocation.y)
                                    <= hitRadius
                                {
                                    model.beginEditGesture()
                                    draggingHandle = (h.segment, h.kind)
                                    break
                                }
                            }
                        }
                        if draggingHandle == nil {
                            let hit = nearestAnchor(
                                of: doc.elements[sel], to: v.startLocation, t: t)
                            if let hit, hit.dist <= hitRadius {
                                model.beginEditGesture()
                                draggingAnchor = (hit.anchor.path, hit.anchor.index)
                                activeAnchor = (hit.anchor.path, hit.anchor.index)
                            }
                        }
                    }
                }
                let target = docPoint(from: v.location, doc: doc, in: size)
                if let h = draggingHandle, let sel = selected, let active = activeAnchor {
                    // Smooth point by default: the opposite handle stays
                    // collinear. Hold Option to break the tangent.
                    let mirror = !NSEvent.modifierFlags.contains(.option)
                    model.moveHandle(
                        element: sel, path: active.path, segment: h.segment, kind: h.kind,
                        to: target, mirror: mirror)
                } else if let d = draggingAnchor, let sel = selected {
                    model.moveAnchor(element: sel, path: d.path, anchor: d.index, to: target)
                } else {
                    // Not editing: rubber-band selection.
                    let a = v.startLocation
                    let b = v.location
                    marquee = CGRect(
                        x: min(a.x, b.x), y: min(a.y, b.y),
                        width: abs(a.x - b.x), height: abs(a.y - b.y))
                    model.editGeneration += 1
                }
            }
            .onEnded { v in
                let wasEditing = draggingAnchor != nil || draggingHandle != nil
                draggingAnchor = nil
                draggingHandle = nil
                gestureBegan = false
                let band = marquee
                marquee = nil
                guard !wasEditing else { return }
                guard let doc = model.document else { return }
                let t = transform(doc: doc, in: size)

                // Rubber-band: select every path with an anchor inside the band.
                if let band, band.width > 4 || band.height > 4 {
                    var picked: Set<Int> = []
                    for (i, el) in doc.elements.enumerated() {
                        for a in Editing.anchors(of: el) {
                            let vpt = CGPoint(
                                x: a.position.x * t.s + t.tx, y: a.position.y * t.s + t.ty)
                            if band.contains(vpt) {
                                picked.insert(i)
                                break
                            }
                        }
                    }
                    model.selectedElements = picked
                    activeAnchor = nil
                    model.selectionChanged()
                    model.editGeneration += 1
                    return
                }

                // A click: hit the topmost path under the cursor. Cmd toggles
                // it in the selection; a plain click replaces the selection.
                let cmd = NSEvent.modifierFlags.contains(.command)
                // ⌘-click near a SELECTED path's outline (not on an anchor or
                // handle): add a point there and make it the active anchor.
                if cmd, let ins = insertionCandidate(at: v.location, doc: doc, t: t, in: size) {
                    model.insertAnchor(
                        element: ins.element, path: ins.path, segment: ins.segment, t: ins.t)
                    model.selectedElements = [ins.element]
                    activeAnchor = (ins.path, ins.anchorIndex)
                    model.selectionChanged()
                    model.editGeneration += 1
                    return
                }
                let hit = elementHit(at: v.location, doc: doc, size: size)
                if let hit {
                    if cmd {
                        if model.selectedElements.contains(hit) {
                            model.selectedElements.remove(hit)
                        } else {
                            model.selectedElements.insert(hit)
                        }
                        activeAnchor = nil
                    } else {
                        model.selectedElements = [hit]
                        // Clicking near an anchor of the single selection also
                        // activates that anchor for handle editing.
                        if let na = nearestAnchor(of: doc.elements[hit], to: v.location, t: t),
                            na.dist <= 20
                        {
                            activeAnchor = (na.anchor.path, na.anchor.index)
                        } else {
                            activeAnchor = nil
                        }
                    }
                } else if !cmd {
                    model.selectedElements = []
                    activeAnchor = nil
                }
                model.selectionChanged()
                model.editGeneration += 1
            }
    }

    /// ⌘-click "add point" hit test: the closest outline point across the
    /// SELECTED paths, within ~6pt on screen, and not over an existing anchor
    /// or handle (those clicks keep their select/drag meaning).
    private func insertionCandidate(at point: CGPoint, doc: VectorDocument, t: T, in size: CGSize)
        -> (element: Int, path: Int, segment: Int, t: Double, anchorIndex: Int)?
    {
        guard !model.selectedElements.isEmpty else { return nil }
        if anchorHit(at: point, in: size, radius: hitRadius) != nil { return nil }
        if let sel = selected, sel < doc.elements.count, let active = activeAnchor {
            for h in Editing.handles(of: doc.elements[sel], path: active.path, anchor: active.index) {
                let hv = CGPoint(x: h.position.x * t.s + t.tx, y: h.position.y * t.s + t.ty)
                if hypot(hv.x - point.x, hv.y - point.y) <= hitRadius { return nil }
            }
        }
        let dp = docPoint(from: point, doc: doc, in: size)
        let tol = 6.0 / Double(t.s)
        var best: (element: Int, path: Int, segment: Int, t: Double, distance: Double)? = nil
        for i in model.selectedElements.sorted() where i < doc.elements.count {
            guard let hit = Editing.closestPoint(of: doc.elements[i], to: dp),
                hit.distance <= tol
            else { continue }
            if best == nil || hit.distance < best!.distance {
                best = (i, hit.path, hit.segment, hit.t, hit.distance)
            }
        }
        return best.map {
            (element: $0.element, path: $0.path, segment: $0.segment, t: $0.t,
                anchorIndex: $0.segment + 1)
        }
    }

    /// Topmost element under a click: fills answer by containment (even-odd),
    /// strokes by distance to their centreline within half their width.
    private func elementHit(at point: CGPoint, doc: VectorDocument, size: CGSize) -> Int? {
        let t = transform(doc: doc, in: size)
        let dp = docPoint(from: point, doc: doc, in: size)
        let cgPoint = CGPoint(x: dp.x, y: dp.y)
        for i in stride(from: doc.elements.count - 1, through: 0, by: -1) {
            switch doc.elements[i] {
            case .fill(let f):
                let path = CGPathBuilder.fillPath(f.geometry, smoothing: model.smoothing)
                if path.contains(cgPoint, using: .evenOdd) { return i }
            case .stroke(let st):
                let tolDoc = max(4.0 / Double(t.s), st.width / 2 + 2 / Double(t.s))
                var bestD = Double.greatestFiniteMagnitude
                let pts = st.points
                if pts.count >= 2 {
                    for j in 0..<(pts.count - 1) {
                        bestD = min(bestD, segmentDistance(dp, pts[j], pts[j + 1]))
                        if bestD <= tolDoc { break }
                    }
                }
                if bestD <= tolDoc { return i }
            }
        }
        return nil
    }

    private func segmentDistance(_ p: Pt, _ a: Pt, _ b: Pt) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-12 {
            return ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot()
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        let px = a.x + t * dx
        let py = a.y + t * dy
        return ((p.x - px) * (p.x - px) + (p.y - py) * (p.y - py)).squareRoot()
    }

    private func nearestAnchor(
        of element: Element, to view: CGPoint, t: T
    ) -> (anchor: Editing.Anchor, dist: CGFloat)? {
        var best: (Editing.Anchor, CGFloat)? = nil
        for a in Editing.anchors(of: element) {
            let v = CGPoint(x: a.position.x * t.s + t.tx, y: a.position.y * t.s + t.ty)
            let d = hypot(v.x - view.x, v.y - view.y)
            if best == nil || d < best!.1 { best = (a, d) }
        }
        return best.map { (anchor: $0.0, dist: $0.1) }
    }

    // MARK: - Break & merge tools

    private func anchorHit(at point: CGPoint, in size: CGSize, radius: CGFloat)
        -> Editing.AnchorRef?
    {
        guard let doc = model.document else { return nil }
        let t = transform(doc: doc, in: size)
        var best: (Editing.AnchorRef, CGFloat)? = nil
        for (i, el) in doc.elements.enumerated() {
            for a in Editing.anchors(of: el) {
                let v = CGPoint(x: a.position.x * t.s + t.tx, y: a.position.y * t.s + t.ty)
                let d = hypot(v.x - point.x, v.y - point.y)
                if d <= radius, best == nil || d < best!.1 {
                    best = (Editing.AnchorRef(element: i, path: a.path, anchor: a.index), d)
                }
            }
        }
        return best?.0
    }

    private func toggleMultiSelect(at point: CGPoint, in size: CGSize) {
        // Shift-click on an anchor: point-level multi-select (merge tool).
        if let ref = anchorHit(at: point, in: size, radius: hitRadius + 3) {
            if multiSel.contains(ref) {
                multiSel.remove(ref)
            } else {
                multiSel.insert(ref)
            }
            model.editGeneration += 1
            return
        }
        // Shift-click on a path: add/remove the SHAPE from the selection.
        guard let doc = model.document,
            let hit = elementHit(at: point, doc: doc, size: size)
        else { return }
        if model.selectedElements.contains(hit) {
            model.selectedElements.remove(hit)
        } else {
            model.selectedElements.insert(hit)
        }
        activeAnchor = nil
        model.selectionChanged()
        model.editGeneration += 1
    }

    private func menuItems(at point: CGPoint, in size: CGSize) -> [(String, () -> Void)] {
        var items: [(String, () -> Void)] = []
        if let ref = anchorHit(at: point, in: size, radius: hitRadius + 3) {
            items.append((
                "Remove Point",
                {
                    model.removeAnchor(element: ref.element, path: ref.path, anchor: ref.anchor)
                    activeAnchor = nil
                    multiSel = []
                }
            ))
            items.append((
                "Break Point",
                {
                    model.breakAnchor(element: ref.element, path: ref.path, anchor: ref.anchor)
                    model.selectedElements = []
                    activeAnchor = nil
                    multiSel = []
                }
            ))
        }
        if multiSel.count >= 2 {
            items.append((
                "Merge \(multiSel.count) Points",
                {
                    model.mergeAnchors(Array(multiSel).sorted {
                        ($0.element, $0.path, $0.anchor) < ($1.element, $1.path, $1.anchor)
                    })
                    model.selectedElements = []
                    activeAnchor = nil
                    multiSel = []
                }
            ))
        }
        if !multiSel.isEmpty {
            items.append((
                "Clear Point Selection",
                {
                    multiSel = []
                    model.editGeneration += 1
                }
            ))
        }
        // "Add Crossing Points" on the clicked path, only when its outline
        // actually crosses another element's (checked lazily on menu build,
        // for the clicked element only).
        if let doc = model.document,
            let hit = elementHit(at: point, doc: doc, size: size),
            model.crossingCount(element: hit) > 0
        {
            items.append((
                "Add Crossing Points",
                {
                    model.selectedElements = [hit]
                    activeAnchor = nil
                    multiSel = []
                    model.selectionChanged()
                    model.addCrossingPoints(element: hit)
                }
            ))
        }
        if !model.selectedElements.isEmpty {
            let n = model.selectedElements.count
            items.append(("Copy \(n) Path(s) as SVG", { model.copySelectionSVG() }))
            items.append(("Copy \(n) Path(s) as Image", { model.copySelectionPNG() }))
            items.append(("Export Selection…", { model.exportSelectionSVG() }))
        }
        return items
    }

    // MARK: - Colours

    private func color(_ paint: Paint) -> Color {
        switch paint {
        case .solid(let c): return rgbColor(c)
        case .linear(let g): return rgbColor(g.stops.first?.color ?? [0, 0, 0])
        case .radial(let g): return rgbColor(g.stops.first?.color ?? [0, 0, 0])
        }
    }

    private func rgbColor(_ c: [UInt8]) -> Color {
        Color(
            red: Double(c.count > 0 ? c[0] : 0) / 255,
            green: Double(c.count > 1 ? c[1] : 0) / 255,
            blue: Double(c.count > 2 ? c[2] : 0) / 255)
    }
}

// MARK: - Right-click context menu (AppKit)

/// Presents an AppKit context menu for right-clicks over the vector canvas.
/// Never claims hit-testing (left clicks belong to editing below); right
/// clicks are taken from the event stream via a local monitor.
struct RightClickCatcher: NSViewRepresentable {
    /// Given the click point (top-left origin) and the view size, return the
    /// menu items to show. Empty list → no menu.
    let items: (CGPoint, CGSize) -> [(String, () -> Void)]

    func makeNSView(context: Context) -> NSView {
        let v = CatcherView()
        v.items = items
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.items = items
    }

    final class CatcherView: NSView {
        var items: ((CGPoint, CGSize) -> [(String, () -> Void)])?
        private var monitor: Any?
        private var actions: [() -> Void] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) {
                [weak self] e in
                guard let self, e.window === self.window else { return e }
                let local = self.convert(e.locationInWindow, from: nil)
                guard self.bounds.contains(local) else { return e }
                let flipped = CGPoint(x: local.x, y: self.bounds.height - local.y)
                let entries = self.items?(flipped, self.bounds.size) ?? []
                guard !entries.isEmpty else { return e }
                let menu = NSMenu()
                self.actions = entries.map { $0.1 }
                // "Submenu|Item" titles group into a submenu (in first-seen
                // order); plain titles stay top-level.
                var submenus: [String: NSMenu] = [:]
                for (i, entry) in entries.enumerated() {
                    let parts = entry.0.split(
                        separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                    let item = NSMenuItem(
                        title: String(parts.last ?? ""), action: #selector(self.fire(_:)),
                        keyEquivalent: "")
                    item.target = self
                    item.tag = i
                    if parts.count == 2 {
                        let name = String(parts[0])
                        let submenu: NSMenu
                        if let existing = submenus[name] {
                            submenu = existing
                        } else {
                            submenu = NSMenu(title: name)
                            let holder = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                            holder.submenu = submenu
                            menu.addItem(holder)
                            submenus[name] = submenu
                        }
                        submenu.addItem(item)
                    } else {
                        menu.addItem(item)
                    }
                }
                NSMenu.popUpContextMenu(menu, with: e, for: self)
                return nil  // consumed
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        @objc private func fire(_ sender: NSMenuItem) {
            guard sender.tag >= 0, sender.tag < actions.count else { return }
            actions[sender.tag]()
        }
    }
}
