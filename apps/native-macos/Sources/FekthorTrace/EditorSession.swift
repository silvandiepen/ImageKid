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

    private(set) var fileURL: URL?
    private(set) var fileKind: FileKind
    private var undoStack: [GraphicDocument] = []
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

    func beginGesture() {
        styleEditKey = nil  // a canvas gesture ends any coalesced panel edit
        undoStack.append(document)
        if undoStack.count > 50 { undoStack.removeFirst() }
        canUndo = true
    }

    func undo() {
        styleEditKey = nil
        guard let doc = undoStack.popLast() else { return }
        document = doc
        canUndo = !undoStack.isEmpty
        dirty = true
        generation += 1
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
        beginGesture()
        mutate { $0.replaceShape(id: id, with: removed) }
        status = "Removed point."
    }

    /// Insert an anchor on a shape's outline at (path, segment, t) — as
    /// reported by `Editing2.closestPoint(of:to:)`. One undo step.
    func insertAnchor(node id: Int, path: Int, segment: Int, t: Double) {
        guard let shape = document.firstShape(id: id) else { return }
        beginGesture()
        let inserted = Editing2.insertAnchor(shape, path: path, segment: segment, t: t)
        mutate { $0.replaceShape(id: id, with: inserted) }
        status = "Added point."
    }

    // MARK: - Z-order (selection, one undo step each)

    func bringForward() { reorderSelection("Brought forward.") { $0.bringForward($1) } }
    func sendBackward() { reorderSelection("Sent backward.") { $0.sendBackward($1) } }
    func bringToFront() { reorderSelection("Brought to front.") { $0.bringToFront($1) } }
    func sendToBack() { reorderSelection("Sent to back.") { $0.sendToBack($1) } }

    private func reorderSelection(
        _ message: String, _ op: (inout GraphicDocument, Set<Int>) -> Void
    ) {
        guard !selection.isEmpty else { return }
        let ids = selection
        beginGesture()
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
        beginGesture()
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
        beginGesture()
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

    // MARK: - Style edits (panel; one undo step per control interaction)

    /// Apply a style mutation to every selected shape. `key` identifies the
    /// control: repeated calls with the same key on the same selection
    /// coalesce into the snapshot taken at the first change (a colour-well
    /// or slider drag is ONE undo step). The drawing style follows suit so
    /// new shapes are born with the last-used style.
    func editSelectionStyle(_ key: String, _ apply: (inout Style) -> Void) {
        var next = drawingStyle
        apply(&next)
        drawingStyle = next
        guard !selection.isEmpty else { return }
        let fullKey = key + "|" + selection.sorted().map(String.init).joined(separator: ",")
        if styleEditKey != fullKey {
            beginGesture()
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
            beginGesture()
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
            beginGesture()
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
        beginGesture()
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

    // MARK: - Shape tools

    /// Insert a freshly drawn primitive with the current drawing style,
    /// select it. One undo step.
    func insertShape(kind: ShapeKind) {
        beginGesture()
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
        beginGesture()
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
        beginGesture()
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
        beginGesture()
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
        beginGesture()
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
        beginGesture()
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
            let svg = SVGWriter.write(document)
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
