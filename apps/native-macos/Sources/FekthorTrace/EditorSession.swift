import AppKit
import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

/// The editor's document session: a GraphicDocument opened from (or saved to)
/// a plain .svg or a .fekthor workfile. Cleanly separate from the trace-only
/// `ConversionModel`. Snapshot undo, node-id selection, dirty tracking, and
/// sandbox-scoped save-in-place.
@MainActor
final class EditorSession: ObservableObject {
    enum FileKind {
        case svg
        case fekthor
    }

    /// The canvas tool. Drawing tools drag out primitives; Select owns the
    /// existing click/marquee/anchor interactions; Pen places anchors one
    /// click (or click-drag) at a time.
    enum Tool: String, CaseIterable {
        case select
        case rect
        case ellipse
        case line
        case pen
    }

    /// One anchor placed by the pen tool. Handles are ABSOLUTE control
    /// points: `handleIn` shapes the segment arriving at this anchor,
    /// `handleOut` the segment leaving it. A corner anchor has neither.
    struct PenAnchor: Equatable {
        var point: Pt
        var handleIn: Pt? = nil
        var handleOut: Pt? = nil
    }

    @Published var document: GraphicDocument
    @Published var selection: Set<Int> = []
    /// App-side node locks (Layers palette): locked nodes are skipped by
    /// canvas hit-testing, marquee and selection. Session-only — the SVG on
    /// disk never carries lock state.
    @Published var lockedNodes: Set<Int> = []
    @Published var canUndo = false
    @Published var dirty = false
    @Published var status: String
    /// Bumped on every mutation so the canvas invalidates.
    @Published var generation = 0
    @Published var tool: Tool = .select {
        didSet {
            // Leaving the pen tool mid-path must never strand invisible
            // state: ≥2 anchors finish as an open path, fewer cancel.
            guard oldValue == .pen, tool != .pen, !penAnchors.isEmpty else { return }
            finishPenPath(closed: false)
        }
    }
    /// The pen tool's in-progress path (empty = no path being drawn). Lives
    /// outside the document — nothing exists to undo until the path lands
    /// as a shape in `finishPenPath`.
    @Published var penAnchors: [PenAnchor] = []
    /// Doc-space hit tolerance for pen bookkeeping (duplicate-anchor trim on
    /// a double-click finish); the canvas refreshes it from its zoom.
    var penTolerance: Double = 0.5
    /// The style newly drawn shapes are born with. Starts at the icon-work
    /// default (no fill, near-black 2pt stroke — SVG's spec-default black
    /// fill is wrong for stroke icons) and follows the last style-panel edit.
    @Published var drawingStyle: Style = EditorSession.defaultDrawingStyle
    /// Free Distort (Transform palette): non-nil while the canvas shows the
    /// 4-corner warp handles. Corner drags recompute every shape from
    /// `originals` (nothing accumulates); the FIRST drag snapshots one
    /// "Distort" undo step for the whole session, Esc restores it.
    struct DistortState {
        var originals: [ShapeNode]
        var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)
        /// tl, tr, br, bl in screen orientation (y down).
        var corners: [Pt]
        var snapshotTaken = false
    }
    @Published var distort: DistortState? = nil
    /// File-local swatches and named styles — the per-file layer under the
    /// workspace's shared sets. Carried INSIDE the SVG as a
    /// `<metadata id="fekthor-meta">` block (FileMeta): loaded here on open,
    /// written back on save, stripped from every export. Works with no
    /// workspace at all — a single detached file keeps its own swatches.
    @Published var fileSwatches: [String] = []
    @Published var fileStyles: [NamedStyle] = []

    /// One undo snapshot: the document as it was BEFORE the labelled
    /// operation ran. The History palette lists these newest-first.
    struct HistoryEntry: Identifiable {
        let id: Int
        let label: String
        let document: GraphicDocument
    }

    private(set) var fileURL: URL?
    private(set) var fileKind: FileKind
    /// The undo stack, with a short op label per snapshot (History palette).
    /// Not @Published — every append rides a `canUndo`/`generation` publish.
    private(set) var history: [HistoryEntry] = []
    private var historyID = 0
    private var scoped = false
    /// Non-nil while a style-panel control is coalescing its edits into the
    /// snapshot taken at its first change (one undo step per control edit).
    private var styleEditKey: String? = nil

    static var defaultDrawingStyle: Style {
        var s = Style()
        s.set("fill", .paint(.none))
        s.set("stroke", .paint(.color(r: 1, g: 1, b: 1)))  // #010101
        s.set("stroke-width", .number(2, unit: nil))
        return s
    }

    init(document: GraphicDocument, fileURL: URL? = nil, fileKind: FileKind = .svg) {
        self.document = document
        self.fileURL = fileURL
        self.fileKind = fileKind
        self.status =
            fileURL.map { "Opened \($0.lastPathComponent)" } ?? "New file — untitled"
        if let url = fileURL {
            scoped = url.startAccessingSecurityScopedResource()
        }
        // Saved gradients come back as url(#id) references over raw defs;
        // fold the modelled ones back into typed paints so they render and
        // edit (EditorGradients.swift). Not an edit: no dirty, no history.
        normalizeGradientReferences()
        // File-local swatches/styles ride in the document's metadata block.
        if let meta = FileMeta.read(from: document) {
            fileSwatches = meta.swatches ?? []
            fileStyles = meta.styles ?? []
        }
    }

    deinit {
        if scoped, let url = fileURL {
            url.stopAccessingSecurityScopedResource()
        }
    }

    static func blank(size: Double = 72) -> EditorSession {
        EditorSession(document: .blank(width: size, height: size))
    }

    /// Open a .svg or .fekthor file.
    static func open(url: URL) throws -> EditorSession {
        if url.pathExtension.lowercased() == "fekthor" {
            let workfile = try Workfile.decode(Data(contentsOf: url))
            guard let artboard = workfile.artboards?.first else {
                throw NSError(
                    domain: "Fekthor", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "This workfile has no embedded artboards (workspaces arrive with the Library update)."
                    ])
            }
            let doc = try SVGReader.read(artboard.svg)
            return EditorSession(document: doc, fileURL: url, fileKind: .fekthor)
        }
        let data = try Data(contentsOf: url)
        let doc = try SVGReader.read(data)
        return EditorSession(document: doc, fileURL: url, fileKind: .svg)
    }

    // MARK: - Mutations (each drag/action snapshots once)

    /// Snapshot the current document as one undo step. `label` is the short
    /// op name the History palette shows ("Move", "Fill colour", "Unite");
    /// untouched call sites keep compiling via the default.
    func beginGesture(label: String = "Edit") {
        styleEditKey = nil  // a canvas gesture ends any coalesced panel edit
        historyID += 1
        history.append(HistoryEntry(id: historyID, label: label, document: document))
        if history.count > 50 { history.removeFirst() }
        canUndo = true
    }

    func undo() {
        styleEditKey = nil
        guard let entry = history.popLast() else { return }
        document = entry.document
        canUndo = !history.isEmpty
        dirty = true
        generation += 1
    }

    /// History palette: revert to an older snapshot (the state BEFORE that
    /// entry's operation ran). The current state is pushed first as a
    /// "Revert" entry, so clicking THAT entry afterwards brings the
    /// reverted-away state back — redo by history. No entries are ever
    /// discarded by a revert; the stack just grows (still capped at 50).
    func revert(toHistoryID id: Int) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        let entry = history[index]
        guard entry.document != document else {
            status = "Already at this state."
            return
        }
        beginGesture(label: "Revert")
        document = entry.document
        dirty = true
        generation += 1
        status = "Reverted to before “\(entry.label)”."
    }

    private func mutate(_ change: (inout GraphicDocument) -> Void) {
        var doc = document
        change(&doc)
        document = doc
        dirty = true
        generation += 1
    }

    func moveAnchor(node id: Int, path: Int, anchor: Int, to: Pt) {
        guard let shape = document.firstShape(id: id) else { return }
        let moved = Editing2.moveAnchor(shape, path: path, anchor: anchor, to: to)
        mutate { $0.replaceShape(id: id, with: moved) }
    }

    func moveHandle(
        node id: Int, path: Int, segment: Int, kind: Editing.HandleKind, to: Pt, mirror: Bool
    ) {
        guard let shape = document.firstShape(id: id) else { return }
        let moved = Editing2.moveHandle(
            shape, path: path, segment: segment, kind: kind, to: to, mirror: mirror)
        mutate { $0.replaceShape(id: id, with: moved) }
    }

    func removeAnchor(node id: Int, path: Int, anchor: Int) {
        guard let shape = document.firstShape(id: id),
            let removed = Editing2.removeAnchor(shape, path: path, anchor: anchor)
        else {
            status = "This point cannot be removed (path is already minimal)."
            return
        }
        beginGesture(label: "Remove point")
        mutate { $0.replaceShape(id: id, with: removed) }
        status = "Removed point."
    }

    /// Insert an anchor on a shape's outline at (path, segment, t) — as
    /// reported by `Editing2.closestPoint(of:to:)`. One undo step.
    func insertAnchor(node id: Int, path: Int, segment: Int, t: Double) {
        guard let shape = document.firstShape(id: id) else { return }
        beginGesture(label: "Add point")
        let inserted = Editing2.insertAnchor(shape, path: path, segment: segment, t: t)
        mutate { $0.replaceShape(id: id, with: inserted) }
        status = "Added point."
    }

    // MARK: - Z-order (selection, one undo step each)

    func bringForward() {
        reorderSelection("Brought forward.", label: "Bring forward") { $0.bringForward($1) }
    }
    func sendBackward() {
        reorderSelection("Sent backward.", label: "Send backward") { $0.sendBackward($1) }
    }
    func bringToFront() {
        reorderSelection("Brought to front.", label: "Bring to front") { $0.bringToFront($1) }
    }
    func sendToBack() {
        reorderSelection("Sent to back.", label: "Send to back") { $0.sendToBack($1) }
    }

    private func reorderSelection(
        _ message: String, label: String, _ op: (inout GraphicDocument, Set<Int>) -> Void
    ) {
        guard !selection.isEmpty else { return }
        let ids = selection
        beginGesture(label: label)
        mutate { op(&$0, ids) }
        status = message
    }

    // MARK: - Group / ungroup

    /// Wrap the selected sibling nodes in a group (placed where the topmost
    /// selected node was); the selection becomes the group.
    func groupSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        var groupID: Int? = nil
        beginGesture(label: "Group")
        mutate { groupID = $0.groupNodes(ids) }
        if let groupID {
            selection = [groupID]
            status = "Grouped \(ids.count) node(s)."
        } else {
            undo()
            status = "Nothing to group."
        }
    }

    /// Dissolve every selected group in place; children inherit the group's
    /// transform/style (composed) and become the selection.
    func ungroupSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        var freed: Set<Int> = []
        beginGesture(label: "Ungroup")
        mutate { freed = $0.ungroupNodes(ids) }
        if freed.isEmpty {
            undo()
            status = "The selection has no groups to ungroup."
        } else {
            selection = freed
            status = "Ungrouped."
        }
    }

    func translateSelection(dx: Double, dy: Double) {
        for id in selection {
            guard let shape = document.firstShape(id: id) else { continue }
            let moved = Editing2.translated(shape, dx: dx, dy: dy)
            mutate { $0.replaceShape(id: id, with: moved) }
        }
    }

    // MARK: - Transforms (scale/rotate drags; caller snapshots once)

    /// Replace several shapes in one mutation. Transform drags recompute
    /// every selected shape from its gesture-start original each event, so
    /// nothing accumulates; the caller calls `beginGesture()` at drag start.
    func updateShapes(_ shapes: [ShapeNode]) {
        guard !shapes.isEmpty else { return }
        mutate { doc in
            for s in shapes { doc.replaceShape(id: s.id, with: s) }
        }
    }

    /// The selected shapes in id order (Transform palette, distort entry).
    func selectionShapes() -> [ShapeNode] {
        selection.sorted().compactMap { document.firstShape(id: $0) }
    }

    /// Union of the selection's geometric bounds (doc coordinates).
    func selectionBounds() -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var out: (minX: Double, minY: Double, maxX: Double, maxY: Double)? = nil
        for shape in selectionShapes() {
            guard let b = Editing2.bounds(of: shape) else { continue }
            if let cur = out {
                out = (
                    Swift.min(cur.minX, b.minX), Swift.min(cur.minY, b.minY),
                    Swift.max(cur.maxX, b.maxX), Swift.max(cur.maxY, b.maxY)
                )
            } else {
                out = b
            }
        }
        return out
    }

    // MARK: - Numeric transforms (Transform palette; one undo step each)

    /// Scale every selected node about a common fixed point (the union box
    /// origin for W/H fields, so the selection keeps its position). Baked
    /// into geometry via the engine's primitive-preserving degrade rules.
    func scaleSelectionNumeric(sx: Double, sy: Double, around c: Pt) {
        let shapes = selectionShapes()
        guard !shapes.isEmpty, sx.isFinite, sy.isFinite,
            abs(sx) > 0.001, abs(sy) > 0.001, sx != 1 || sy != 1
        else { return }
        beginGesture(label: "Resize")
        updateShapes(shapes.map { TransformOps.scaledNumeric($0, sx: sx, sy: sy, around: c) })
        status = "Resized."
    }

    /// Move the selection so its union box origin lands at (x, y).
    func moveSelectionTo(x: Double? = nil, y: Double? = nil) {
        guard let box = selectionBounds() else { return }
        let dx = (x ?? box.minX) - box.minX
        let dy = (y ?? box.minY) - box.minY
        guard abs(dx) > 1e-9 || abs(dy) > 1e-9 else { return }
        beginGesture(label: "Move")
        translateSelection(dx: dx, dy: dy)
        status = "Moved."
    }

    /// Rotate the selection by `degrees` (positive clockwise on screen)
    /// around the union box centre — geometry-baked, never a transform.
    func rotateSelectionNumeric(degrees: Double) {
        let shapes = selectionShapes()
        guard !shapes.isEmpty, degrees.isFinite, abs(degrees) > 1e-9,
            let box = selectionBounds()
        else { return }
        let c = Pt((box.minX + box.maxX) / 2, (box.minY + box.maxY) / 2)
        beginGesture(label: "Rotate")
        updateShapes(shapes.map { TransformOps.rotatedNumeric($0, degrees: degrees, around: c) })
        status = String(format: "Rotated %.1f°.", degrees)
    }

    /// Skew (shear) the selection around the union box centre. Skew has no
    /// primitive form, so touched nodes become paths — the status says so
    /// the first time a primitive converts.
    func skewSelection(xDegrees: Double, yDegrees: Double) {
        let shapes = selectionShapes()
        guard !shapes.isEmpty, xDegrees.isFinite, yDegrees.isFinite,
            abs(xDegrees) > 1e-9 || abs(yDegrees) > 1e-9,
            abs(xDegrees) < 89, abs(yDegrees) < 89,
            let box = selectionBounds()
        else { return }
        let c = Pt((box.minX + box.maxX) / 2, (box.minY + box.maxY) / 2)
        let hadPrimitives = shapes.contains { shape in
            if case .path = shape.kind { return false }
            return true
        }
        beginGesture(label: "Skew")
        updateShapes(
            shapes.map {
                TransformOps.skewed($0, xDegrees: xDegrees, yDegrees: yDegrees, around: c)
            })
        status = hadPrimitives ? "Skewed — shapes converted to paths." : "Skewed."
    }

    // MARK: - Free Distort (Transform palette; ONE "Distort" undo step)

    /// Enter distort mode: the canvas swaps the selection chrome for four
    /// independent corner handles. Nothing mutates until a corner moves.
    func beginDistort() {
        let shapes = selectionShapes()
        guard !shapes.isEmpty, let box = selectionBounds(),
            box.maxX - box.minX > 1e-9, box.maxY - box.minY > 1e-9
        else {
            status = "Select something with area to distort."
            return
        }
        tool = .select
        distort = DistortState(
            originals: shapes, bounds: box,
            corners: [
                Pt(box.minX, box.minY), Pt(box.maxX, box.minY),
                Pt(box.maxX, box.maxY), Pt(box.minX, box.maxY),
            ])
        status = "Free Distort — drag the corners; Return commits, Esc cancels."
    }

    /// A corner drag event: the first one snapshots the single "Distort"
    /// undo step; every event rewarps all shapes from their originals.
    /// Distort always degrades to paths (no primitive survives a warp).
    func distortDrag(corner: Int, to p: Pt) {
        guard var state = distort, state.corners.indices.contains(corner) else { return }
        if !state.snapshotTaken {
            beginGesture(label: "Distort")
            state.snapshotTaken = true
        }
        state.corners[corner] = p
        distort = state
        let c = state.corners
        updateShapes(
            state.originals.map {
                TransformOps.distorted(
                    $0, corners: (tl: c[0], tr: c[1], br: c[2], bl: c[3]),
                    from: state.bounds)
            })
    }

    /// Return / Commit button: keep the warp, leave the mode.
    func commitDistort() {
        guard let state = distort else { return }
        distort = nil
        generation += 1
        status = state.snapshotTaken ? "Distorted." : "Free Distort left (nothing moved)."
    }

    /// Esc / Cancel button: restore the pre-distort document, leave the mode.
    func cancelDistort() {
        guard let state = distort else { return }
        distort = nil
        if state.snapshotTaken {
            undo()
        } else {
            generation += 1
        }
        status = "Distort cancelled."
    }

    // MARK: - Style edits (panel; one undo step per control interaction)

    /// Apply a style mutation to every selected shape. `key` identifies the
    /// control: repeated calls with the same key on the same selection
    /// coalesce into the snapshot taken at the first change (a colour-well
    /// or slider drag is ONE undo step). The drawing style follows suit so
    /// new shapes are born with the last-used style.
    func editSelectionStyle(_ key: String, label: String? = nil, _ apply: (inout Style) -> Void) {
        var next = drawingStyle
        apply(&next)
        drawingStyle = next
        guard !selection.isEmpty else { return }
        let fullKey = key + "|" + selection.sorted().map(String.init).joined(separator: ",")
        if styleEditKey != fullKey {
            beginGesture(label: label ?? Self.styleEditLabel(key))
            styleEditKey = fullKey  // after beginGesture (which clears it)
        }
        let ids = selection
        mutate { doc in
            for id in ids {
                guard var shape = doc.firstShape(id: id) else { continue }
                apply(&shape.style)
                doc.replaceShape(id: id, with: shape)
            }
        }
    }

    /// End the current coalesced style edit (control lost focus / slider up).
    func endStyleEdit() {
        styleEditKey = nil
    }

    /// The History label for a style-panel edit key.
    private static func styleEditLabel(_ key: String) -> String {
        switch key {
        case "fill": return "Fill colour"
        case "stroke": return "Stroke colour"
        case "stroke-width": return "Stroke width"
        case "opacity": return "Opacity"
        case "dash": return "Dash pattern"
        case "cap": return "Stroke cap"
        case "join": return "Stroke join"
        case "fill-rule": return "Fill rule"
        default: return key.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    // MARK: - Corner radius (Corners palette)

    /// A rect's authored geometry, captured by the Corners palette when the
    /// chain toggle decouples the corners — the node itself may become a
    /// `.path` right after, so per-corner edits rebuild from THIS.
    struct CornerRect: Equatable {
        var id: Int
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// Uniform corner radius on every selected rect. Keeps kind `.rect` —
    /// the radius lands in `rx` (SVG's rx==ry default), so the primitive
    /// still round-trips. Repeated calls from the same control (the radius
    /// slider) coalesce into one undo step, like style edits.
    func setRectRadius(_ radius: Double) {
        let ids = selection.sorted().filter { id in
            if case .rect = document.firstShape(id: id)?.kind { return true }
            return false
        }
        guard !ids.isEmpty else { return }
        let key = "corner-radius|" + ids.map(String.init).joined(separator: ",")
        if styleEditKey != key {
            beginGesture(label: "Corner radius")
            styleEditKey = key
        }
        mutate { doc in
            for id in ids {
                guard var shape = doc.firstShape(id: id),
                    case .rect(let x, let y, let w, let h, _, _) = shape.kind
                else { continue }
                let r = max(0, min(radius, min(w, h) / 2))
                shape.kind = .rect(
                    x: x, y: y, width: w, height: h, rx: r > 0.001 ? r : nil, ry: nil)
                doc.replaceShape(id: id, with: shape)
            }
        }
    }

    /// Per-corner radii: no rect form exists for decoupled corners, so each
    /// node becomes a `.path` built by `CornerRadius.roundedRectPath` from
    /// its captured geometry (radii clamped pairwise in the engine). One
    /// undo snapshot per control edit (repeated calls coalesce until
    /// `endStyleEdit`); the status notes the conversion the first time.
    func setRectPerCornerRadii(
        rects: [CornerRect],
        topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double
    ) {
        guard !rects.isEmpty else { return }
        let key = "corner-per|" + rects.map { String($0.id) }.joined(separator: ",")
        if styleEditKey != key {
            beginGesture(label: "Corner radii")
            styleEditKey = key
        }
        var converted = false
        mutate { doc in
            for rect in rects {
                guard var shape = doc.firstShape(id: rect.id) else { continue }
                if case .rect = shape.kind { converted = true }
                shape.kind = .path([
                    CornerRadius.roundedRectPath(
                        x: rect.x, y: rect.y, width: rect.width, height: rect.height,
                        topLeft: topLeft, topRight: topRight,
                        bottomRight: bottomRight, bottomLeft: bottomLeft)
                ])
                doc.replaceShape(id: rect.id, with: shape)
            }
        }
        if converted {
            status = "Rect converted to path for per-corner radii."
        }
    }

    /// Re-link after per-corner edits: the captured rects come back as
    /// native `.rect` primitives with one uniform radius (round-trip
    /// restored). One undo step.
    func relinkRectRadius(rects: [CornerRect], radius: Double) {
        guard !rects.isEmpty else { return }
        styleEditKey = nil
        beginGesture(label: "Link corners")
        mutate { doc in
            for rect in rects {
                guard var shape = doc.firstShape(id: rect.id) else { continue }
                let r = max(0, min(radius, min(rect.width, rect.height) / 2))
                shape.kind = .rect(
                    x: rect.x, y: rect.y, width: rect.width, height: rect.height,
                    rx: r > 0.001 ? r : nil, ry: nil)
                doc.replaceShape(id: rect.id, with: shape)
            }
        }
        status = "Corners linked — rect restored."
    }

    // MARK: - Live corners (any shape)

    /// A shape with corner radius applied through the engine's fillet op.
    /// The one primitive fast path survives: a plain rect with ALL corners
    /// selected and a uniform radius keeps its native `.rect` rx (SVG
    /// round-trip); everything else pathifies first (`Editing2.editable`)
    /// and fillets its line-line corner anchors. `corners` maps subpath
    /// index → anchor indices; nil rounds every corner of every subpath.
    /// V1 is destructive (Illustrator pre-live-corners): geometry changes,
    /// nothing is stored.
    static func roundedShape(
        _ shape: ShapeNode, radius: Double, corners: [Int: Set<Int>]? = nil
    ) -> ShapeNode {
        if corners == nil, shape.transform == nil,
            case .rect(let x, let y, let w, let h, _, _) = shape.kind
        {
            var out = shape
            let r = max(0, min(radius, min(w, h) / 2))
            out.kind = .rect(
                x: x, y: y, width: w, height: h, rx: r > 0.001 ? r : nil, ry: nil)
            return out
        }
        var out = Editing2.editable(shape)
        guard case .path(let paths) = out.kind else { return shape }
        out.kind = .path(
            paths.enumerated().map { pi, rp in
                LiveCorners.rounded(
                    path: rp, radius: radius, corners: corners.map { $0[pi] ?? [] })
            })
        return out
    }

    /// Corner radius on every selected shape (Corners palette, canvas
    /// corner dots): whole-shape when `onlySelectedAnchors` is nil,
    /// per-anchor otherwise. Repeated calls from the same control coalesce
    /// into one undo step, like style edits.
    func setCornerRadius(radius: Double, onlySelectedAnchors anchors: [Int: Set<Int>]? = nil) {
        let ids = selection.sorted().filter { document.firstShape(id: $0) != nil }
        guard !ids.isEmpty, radius.isFinite, radius >= 0 else { return }
        let key = "live-corner|" + ids.map(String.init).joined(separator: ",")
        if styleEditKey != key {
            beginGesture(label: "Corner radius")
            styleEditKey = key
        }
        mutate { doc in
            for id in ids {
                guard let shape = doc.firstShape(id: id) else { continue }
                doc.replaceShape(
                    id: id, with: Self.roundedShape(shape, radius: radius, corners: anchors))
            }
        }
    }

    // MARK: - File-local swatches & styles (FileMeta)

    /// The metadata block the next save writes (empty = none).
    private var fileMeta: FileMeta.Meta {
        FileMeta.Meta(
            swatches: fileSwatches.isEmpty ? nil : fileSwatches,
            styles: fileStyles.isEmpty ? nil : fileStyles)
    }

    func addFileSwatch(_ hex: String) {
        guard !fileSwatches.contains(hex) else { return }
        fileSwatches.append(hex)
        dirty = true
        status = "Added \(hex) to this file's swatches."
    }

    func removeFileSwatch(_ hex: String) {
        guard fileSwatches.contains(hex) else { return }
        fileSwatches.removeAll { $0 == hex }
        dirty = true
    }

    /// Replace the file-local styles wholesale (Styles palette edits).
    func setFileStyles(_ styles: [NamedStyle]) {
        guard styles != fileStyles else { return }
        fileStyles = styles
        dirty = true
    }

    // MARK: - Shape tools

    /// Insert a freshly drawn primitive with the current drawing style,
    /// select it. One undo step.
    func insertShape(kind: ShapeKind) {
        beginGesture(label: "Draw \(tool.rawValue)")
        let node = ShapeNode(id: document.nextNodeID, kind: kind, style: drawingStyle)
        mutate { $0.nodes.append(.shape(node)) }
        selection = [node.id]
        status = "Added \(tool.rawValue)."
    }

    // MARK: - Pen tool (path under construction; commits as ONE shape)

    /// Place the next anchor (a corner until a drag pulls handles out).
    func penAppendAnchor(at p: Pt) {
        penAnchors.append(PenAnchor(point: p))
        generation += 1
    }

    /// Live handle pull on the newest anchor: the outgoing control follows
    /// the cursor; with `mirror` the incoming control stays its reflection
    /// (⌥ breaks the symmetry and leaves the incoming handle where it was).
    func penSetLastHandles(out: Pt, mirror: Bool) {
        guard var last = penAnchors.last else { return }
        last.handleOut = out
        if mirror {
            last.handleIn = Pt(2 * last.point.x - out.x, 2 * last.point.y - out.y)
        }
        penAnchors[penAnchors.count - 1] = last
        generation += 1
    }

    /// Backspace while drawing: drop the newest anchor (with its handles).
    /// Removing the only anchor cancels the path.
    func penRemoveLastAnchor() {
        guard !penAnchors.isEmpty else { return }
        penAnchors.removeLast()
        generation += 1
        if penAnchors.isEmpty { status = "Path cancelled." }
    }

    /// Esc: throw the in-progress path away entirely.
    func cancelPenPath() {
        guard !penAnchors.isEmpty else { return }
        penAnchors = []
        generation += 1
        status = "Path cancelled."
    }

    /// The path as placed so far (open), for the canvas preview.
    func penPreviewPath() -> RefinedPath? {
        guard penAnchors.count >= 2 else { return nil }
        return Self.penPath(penAnchors, closed: false)
    }

    /// Commit the pen path as ONE `.path` ShapeNode with the drawing style;
    /// one undo snapshot; the shape becomes the selection and the tool stays
    /// pen (Illustrator convention). `trimDuplicate` drops a trailing anchor
    /// that coincides with the previous one — the double-click finish placed
    /// its second click as an anchor before the finish arrived.
    func finishPenPath(closed: Bool, trimDuplicate: Bool = false) {
        if trimDuplicate, penAnchors.count >= 2 {
            let a = penAnchors[penAnchors.count - 2].point
            let b = penAnchors[penAnchors.count - 1].point
            if (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
                <= penTolerance * penTolerance
            {
                penAnchors.removeLast()
            }
        }
        guard penAnchors.count >= 2 else {
            cancelPenPath()
            return
        }
        let path = Self.penPath(penAnchors, closed: closed)
        penAnchors = []
        beginGesture(label: "Pen path")
        let node = ShapeNode(id: document.nextNodeID, kind: .path([path]), style: drawingStyle)
        mutate { $0.nodes.append(.shape(node)) }
        selection = [node.id]
        status = closed ? "Added closed path." : "Added path."
    }

    /// Anchors → RefinedPath: neighbours with no handles between them join
    /// with a line; any handle makes the span a cubic (a missing control
    /// degenerates onto its anchor, which is exactly SVG's smooth-corner
    /// behaviour).
    static func penPath(_ anchors: [PenAnchor], closed: Bool) -> RefinedPath {
        func segment(from a: PenAnchor, to b: PenAnchor) -> RefinedSegment {
            if a.handleOut == nil && b.handleIn == nil { return .line(to: b.point) }
            return .cubic(c1: a.handleOut ?? a.point, c2: b.handleIn ?? b.point, to: b.point)
        }
        var segments: [RefinedSegment] = []
        for i in 1..<anchors.count {
            segments.append(segment(from: anchors[i - 1], to: anchors[i]))
        }
        if closed, let last = anchors.last, let first = anchors.first {
            segments.append(segment(from: last, to: first))
        }
        return RefinedPath(start: anchors[0].point, segments: segments, closed: closed)
    }

    // MARK: - Align & distribute (Object ▸ Align)

    /// Align the selection: 2+ nodes align to their collective bounds, a
    /// single node aligns to the artboard. One undo step, only if something
    /// actually moved.
    func alignSelection(_ edge: AlignEdge) {
        guard !selection.isEmpty else {
            status = "Select something to align."
            return
        }
        let next =
            selection.count >= 2
            ? Align.align(selection, edge: edge, in: document)
            : Align.alignToArtboard(selection, edge: edge, in: document)
        guard next != document else {
            status = "Already aligned."
            return
        }
        beginGesture(label: "Align")
        mutate { $0 = next }
        status = selection.count >= 2 ? "Aligned selection." : "Aligned to artboard."
    }

    /// Equalise the gaps between 3+ selected nodes along an axis.
    func distributeSelection(_ axis: DistributeAxis) {
        guard selection.count >= 3 else {
            status = "Select three or more nodes to distribute."
            return
        }
        let next = Align.distribute(selection, axis: axis, in: document)
        guard next != document else {
            status = "Already distributed."
            return
        }
        beginGesture(label: "Distribute")
        mutate { $0 = next }
        status = "Distributed selection."
    }

    // MARK: - Raster export (File ▸ Export)

    /// The default export file stem: the open file's name, else "untitled".
    private var exportStem: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "untitled"
    }

    /// Export PNG via a save panel with a scale popup accessory (1×/2×/4×
    /// pixels per document unit, defaulting 1×).
    func exportPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = exportStem + ".png"
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["1×", "2×", "4×"])
        let label = NSTextField(labelWithString: "Scale:")
        let stack = NSStackView(views: [label, popup])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 200, height: 40)
        panel.accessoryView = stack
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scale = [1.0, 2.0, 4.0][max(0, popup.indexOfSelectedItem)]
        guard let data = RasterExport.pngData(document, scale: scale) else {
            status = "PNG export failed (empty artboard?)."
            return
        }
        writeExport(data, to: url)
    }

    /// Export a single-page vector PDF (1 document unit = 1 pt).
    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = exportStem + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = RasterExport.pdfData(document) else {
            status = "PDF export failed (empty artboard?)."
            return
        }
        writeExport(data, to: url)
    }

    private func writeExport(_ data: Data, to url: URL) {
        do {
            try data.write(to: url)
            status = "Exported \(url.lastPathComponent)"
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Path booleans

    /// Combine the selected shapes (2+) with a boolean op, in document
    /// order (first = subject). The result replaces the first input in
    /// place — adopting its id/style, as `PathOps.combine` guarantees —
    /// and the other inputs are removed. One undo snapshot; the result
    /// becomes the selection.
    func combineSelection(_ op: BoolOp) {
        guard selection.count >= 2 else {
            status = "Select two or more shapes to combine."
            return
        }
        var ordered: [ShapeNode] = []
        func collect(_ nodes: [GraphicNode]) {
            for node in nodes {
                switch node {
                case .raw: continue
                case .group(let g): collect(g.children)
                case .shape(let s):
                    if selection.contains(s.id) { ordered.append(s) }
                }
            }
        }
        collect(document.nodes)
        guard ordered.count >= 2 else {
            status = "Select two or more shapes to combine (groups don't combine)."
            return
        }
        guard let combined = PathOps.combine(ordered, op: op) else {
            status = "These shapes cannot be combined (open paths, or an empty result)."
            return
        }
        let removeIDs = Set(ordered.map(\.id)).subtracting([combined.id])
        let opLabel: String
        switch op {
        case .union: opLabel = "Unite"
        case .subtract: opLabel = "Subtract"
        case .intersect: opLabel = "Intersect"
        case .exclude: opLabel = "Exclude"
        }
        beginGesture(label: opLabel)
        mutate { doc in
            doc.replaceShape(id: combined.id, with: combined)
            func prune(_ nodes: inout [GraphicNode]) {
                nodes.removeAll {
                    if case .shape(let s) = $0 { return removeIDs.contains(s.id) }
                    return false
                }
                for i in nodes.indices {
                    if case .group(var g) = nodes[i] {
                        prune(&g.children)
                        nodes[i] = .group(g)
                    }
                }
            }
            prune(&doc.nodes)
        }
        selection = [combined.id]
        let label: String
        switch op {
        case .union: label = "United"
        case .subtract: label = "Subtracted"
        case .intersect: label = "Intersected"
        case .exclude: label = "Excluded"
        }
        status = "\(label) \(ordered.count) shapes."
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        beginGesture(label: "Delete")
        let ids = selection
        mutate { doc in
            func prune(_ nodes: inout [GraphicNode]) {
                nodes.removeAll { ids.contains($0.id) }
                for i in nodes.indices {
                    if case .group(var g) = nodes[i] {
                        prune(&g.children)
                        nodes[i] = .group(g)
                    }
                }
            }
            prune(&doc.nodes)
        }
        selection = []
        status = "Deleted \(ids.count) node(s)."
    }

    // MARK: - Layers palette (visibility, lock, rename, sibling reorder)

    /// Set/clear `display: none` on any node (shape or group). One labelled
    /// undo step per click. Hiding also drops the node from the selection —
    /// an invisible node must not keep transform handles.
    func setNodeHidden(_ id: Int, _ hidden: Bool) {
        beginGesture(label: hidden ? "Hide" : "Show")
        var touched = false
        mutate { doc in
            touched = doc.updateNode(id: id) { attributes, style in
                if hidden {
                    style.set("display", .raw("none"))
                } else {
                    style.remove("display")
                    // A presentation attribute `display="none"` would keep
                    // the node hidden — clear it too.
                    attributes.extras.removeAll { $0.name == "display" }
                }
            }
        }
        guard touched else {
            undo()
            return
        }
        if hidden { selection.remove(id) }
        status = hidden ? "Hidden." : "Shown."
    }

    /// Lock/unlock a node (app-side only; no document mutation, no undo).
    /// Locking deselects — a locked node cannot be manipulated.
    func setNodeLocked(_ id: Int, _ locked: Bool) {
        if locked {
            lockedNodes.insert(id)
            selection.remove(id)
        } else {
            lockedNodes.remove(id)
        }
        generation += 1
    }

    /// Rename a node: writes (or clears) its `data-name` attribute — the
    /// name the Layers palette shows first. One undo step.
    func renameNode(_ id: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        beginGesture(label: "Rename")
        var touched = false
        mutate { doc in
            touched = doc.updateNode(id: id) { attributes, _ in
                if trimmed.isEmpty {
                    attributes.extras.removeAll { $0.name == "data-name" }
                } else if let i = attributes.extras.firstIndex(where: { $0.name == "data-name" }) {
                    attributes.extras[i].value = trimmed
                } else {
                    attributes.extras.append(XMLAttr(name: "data-name", value: trimmed))
                }
            }
        }
        if !touched { undo() }
    }

    /// Layers drag-reorder: move `moved` to sit visually ABOVE `target`
    /// (both must share a sibling array; groups move with their subtree).
    /// One "Reorder" undo step when the order actually changes.
    func reorderNode(_ moved: Int, above target: Int) {
        guard moved != target else { return }
        var next = document
        var reordered = false
        func walk(_ arr: inout [GraphicNode]) -> Bool {
            let im = arr.firstIndex { $0.id == moved }
            let it = arr.firstIndex { $0.id == target }
            if let im, let it {
                let node = arr.remove(at: im)
                // Visually above = drawn later: insert right AFTER target.
                arr.insert(node, at: (im < it ? it - 1 : it) + 1)
                reordered = true
                return true
            }
            // One of the two lives here, the other elsewhere: not siblings.
            if im != nil || it != nil { return true }
            for i in arr.indices {
                if case .group(var g) = arr[i] {
                    let done = walk(&g.children)
                    arr[i] = .group(g)
                    if done { return true }
                }
            }
            return false
        }
        _ = walk(&next.nodes)
        guard reordered else {
            status = "Layers reorder works between siblings — move nodes in or out with Group/Ungroup."
            return
        }
        guard next != document else { return }
        beginGesture(label: "Reorder")
        mutate { $0 = next }
        status = "Reordered."
    }

    // MARK: - Named styles (Styles palette)

    /// Apply a workspace named style to every selected SHAPE — groups are
    /// skipped (the engine's `NamedStyles.apply` binds shapes). `roster` is
    /// the full set of workspace style names so a re-style swaps its binding
    /// class cleanly. One undo step.
    func applyNamedStyle(_ style: NamedStyle, roster: [String]) {
        let ids = selection.sorted().filter { document.firstShape(id: $0) != nil }
        guard !ids.isEmpty else {
            status = "Select a shape to apply “\(style.name)”."
            return
        }
        beginGesture(label: "Apply style")
        mutate { doc in
            for id in ids {
                guard let shape = doc.firstShape(id: id) else { continue }
                doc.replaceShape(
                    id: id, with: NamedStyles.apply(style, to: shape, replacing: roster))
            }
        }
        status = "Applied “\(style.name)” to \(ids.count) node\(ids.count == 1 ? "" : "s")."
    }

    /// Snapshot the single selected shape's paint style as a named style
    /// (nil when the selection is not exactly one shape).
    func captureNamedStyle(named name: String) -> NamedStyle? {
        guard selection.count == 1, let id = selection.first,
            let shape = document.firstShape(id: id)
        else { return nil }
        return NamedStyles.capture(from: shape, name: name)
    }

    /// Rewrite the open document's nodes bound to `style` after its
    /// declarations changed (engine propagate over a one-document dict).
    /// One labelled undo step; a no-op when nothing here is bound.
    func propagateNamedStyle(_ style: NamedStyle, label: String = "Update style") {
        let changed = NamedStyles.propagate(style, docs: ["open": document])
        guard let next = changed["open"] else { return }
        beginGesture(label: label)
        mutate { $0 = next }
    }

    /// Style rename: retag the binding class on every bound node of the
    /// open document. One undo step when anything changed.
    func retagClassInDocument(from old: String, to new: String, label: String = "Rename style") {
        var changed = false
        let nodes = ClassRetag.rename(document.nodes, old: old, new: new, changed: &changed)
        guard changed else { return }
        beginGesture(label: label)
        mutate { $0.nodes = nodes }
    }

    /// Remove a class token from every node of the open document (style
    /// delete with "strip"). One undo step when anything changed.
    func stripClassInDocument(_ token: String, label: String = "Delete style") {
        var changed = false
        let nodes = ClassRetag.strip(document.nodes, token: token, changed: &changed)
        guard changed else { return }
        beginGesture(label: label)
        mutate { $0.nodes = nodes }
    }

    // MARK: - Classes (Classes editor)

    /// Add a user class to every selected node missing it (shapes AND
    /// groups). One undo step for the whole selection.
    func addClassToSelection(_ token: String) {
        let ids = selection.sorted().filter { id in
            guard let node = document.firstNode(id: id) else { return false }
            return !ClassTokens.list(node.nodeAttributes).contains(token)
        }
        guard !ids.isEmpty else {
            status = "Every selected node already has “\(token)”."
            return
        }
        beginGesture(label: "Add class")
        mutate { doc in
            for id in ids {
                doc.updateNode(id: id) { attributes, _ in
                    var classes = ClassTokens.list(attributes)
                    classes.append(token)
                    attributes = ClassTokens.setting(attributes, to: classes)
                }
            }
        }
        status = "Added class “\(token)”."
    }

    /// Remove a class token from every selected node carrying it. One undo
    /// step.
    func removeClassFromSelection(_ token: String) {
        let ids = selection.sorted().filter { id in
            guard let node = document.firstNode(id: id) else { return false }
            return ClassTokens.list(node.nodeAttributes).contains(token)
        }
        guard !ids.isEmpty else { return }
        beginGesture(label: "Remove class")
        mutate { doc in
            for id in ids {
                doc.updateNode(id: id) { attributes, _ in
                    let classes = ClassTokens.list(attributes).filter { $0 != token }
                    attributes = ClassTokens.setting(attributes, to: classes)
                }
            }
        }
        status = "Removed class “\(token)”."
    }

    // MARK: - Saving

    func save() {
        guard let url = fileURL else {
            saveAs()
            return
        }
        write(to: url)
    }

    func saveAs() {
        let panel = NSSavePanel()
        let svgType = UTType(filenameExtension: "svg") ?? .xml
        let fekthorType = UTType(filenameExtension: "fekthor") ?? .json
        panel.allowedContentTypes = fileKind == .fekthor ? [fekthorType, svgType] : [svgType, fekthorType]
        panel.nameFieldStringValue =
            fileURL?.lastPathComponent ?? (fileKind == .fekthor ? "untitled.fekthor" : "untitled.svg")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileKind = url.pathExtension.lowercased() == "fekthor" ? .fekthor : .svg
        fileURL = url
        write(to: url)
    }

    private func write(to url: URL) {
        do {
            // File-local swatches/styles land in (or leave) the metadata
            // block at save time; the in-memory document stays untouched.
            let svg = SVGWriter.write(FileMeta.writing(fileMeta, to: document))
            switch fileKind {
            case .svg:
                try svg.write(to: url, atomically: true, encoding: .utf8)
            case .fekthor:
                let name = url.deletingPathExtension().lastPathComponent
                let workfile = Workfile(artboards: [.init(name: name, svg: svg)])
                try workfile.encoded().write(to: url)
            }
            dirty = false
            status = "Saved \(url.lastPathComponent)"
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - App-side tree access (any node, shape OR group)

extension GraphicNode {
    /// The node's attributes (raw nodes have none — empty placeholder).
    var nodeAttributes: NodeAttributes {
        switch self {
        case .shape(let s): return s.attributes
        case .group(let g): return g.attributes
        case .raw: return NodeAttributes()
        }
    }
}

extension GraphicDocument {
    /// Find any node (shape or group) by id, depth-first.
    func firstNode(id: Int) -> GraphicNode? {
        func walk(_ nodes: [GraphicNode]) -> GraphicNode? {
            for n in nodes {
                if n.id == id, case .raw = n { return nil }
                if n.id == id { return n }
                if case .group(let g) = n, let hit = walk(g.children) { return hit }
            }
            return nil
        }
        return walk(nodes)
    }

    /// Edit any node's attributes + inline style in place (shape or group).
    /// Returns false when the id is absent (or a raw node).
    @discardableResult
    mutating func updateNode(
        id: Int, _ edit: (inout NodeAttributes, inout Style) -> Void
    ) -> Bool {
        func walk(_ nodes: inout [GraphicNode]) -> Bool {
            for i in nodes.indices {
                switch nodes[i] {
                case .shape(var s) where s.id == id:
                    edit(&s.attributes, &s.style)
                    nodes[i] = .shape(s)
                    return true
                case .group(var g):
                    if g.id == id {
                        edit(&g.attributes, &g.style)
                        nodes[i] = .group(g)
                        return true
                    }
                    if walk(&g.children) {
                        nodes[i] = .group(g)
                        return true
                    }
                default:
                    break
                }
            }
            return false
        }
        return walk(&nodes)
    }
}
