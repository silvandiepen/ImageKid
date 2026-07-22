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
    /// existing click/marquee/anchor interactions.
    enum Tool: String, CaseIterable {
        case select
        case rect
        case ellipse
        case line
    }

    @Published var document: GraphicDocument
    @Published var selection: Set<Int> = []
    @Published var canUndo = false
    @Published var dirty = false
    @Published var status: String
    /// Bumped on every mutation so the canvas invalidates.
    @Published var generation = 0
    @Published var tool: Tool = .select
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
