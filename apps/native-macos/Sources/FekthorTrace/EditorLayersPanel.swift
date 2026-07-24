import AppKit
import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

// The Layers palette: the document's node tree, topmost (newest) first —
// layer-panel convention — with disclosure for groups, a small vector
// thumbnail per node, the display name (data-name → id → kind), an eye
// toggle (writes `display: none` inline; the canvas render/hit paths honour
// it) and an app-side lock (locked ids live in EditorSession; hit-testing,
// marquee and selection skip them). Rows select (⇧/⌘ toggles), double-click
// renames (data-name), dragging reorders within a sibling array as one
// "Reorder" undo step. Selection stays bidirectional: the rows highlight
// whatever the canvas selects.

struct LayersPanelContent: View {
    @ObservedObject var session: EditorSession

    /// Collapsed group ids (everything starts expanded).
    @State private var collapsed: Set<Int> = []
    @State private var editingID: Int? = nil
    @State private var editText = ""
    @State private var draggedID: Int? = nil
    @State private var dropTargetID: Int? = nil

    struct Row: Identifiable {
        let id: Int
        let depth: Int
        let node: GraphicNode
        let isGroup: Bool
    }

    /// Flattened visible rows: sibling arrays reversed (later in document
    /// order = drawn on top = higher in the list), groups indent children.
    private var rows: [Row] {
        var out: [Row] = []
        func walk(_ nodes: [GraphicNode], depth: Int) {
            for node in nodes.reversed() {
                switch node {
                case .raw:
                    continue  // defs/style blocks are not layers
                case .shape:
                    out.append(Row(id: node.id, depth: depth, node: node, isGroup: false))
                case .group(let g):
                    out.append(Row(id: g.id, depth: depth, node: node, isGroup: true))
                    if !collapsed.contains(g.id) {
                        walk(g.children, depth: depth + 1)
                    }
                }
            }
        }
        walk(session.document.nodes, depth: 0)
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Topmost first · drag to reorder siblings")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if rows.isEmpty {
                Text("The document has no nodes yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { row in
                            LayerRowView(
                                session: session,
                                row: row,
                                selected: session.selection.contains(row.id),
                                hidden: row.node.isHiddenNode,
                                locked: session.lockedNodes.contains(row.id),
                                isCollapsed: collapsed.contains(row.id),
                                isDropTarget: dropTargetID == row.id,
                                editingID: $editingID,
                                editText: $editText,
                                draggedID: $draggedID,
                                dropTargetID: $dropTargetID,
                                onToggleCollapse: { toggleCollapse(row.id) })
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggleCollapse(_ id: Int) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
    }
}

// MARK: - One layer row

private struct LayerRowView: View {
    let session: EditorSession
    let row: LayersPanelContent.Row
    let selected: Bool
    let hidden: Bool
    let locked: Bool
    let isCollapsed: Bool
    let isDropTarget: Bool
    @Binding var editingID: Int?
    @Binding var editText: String
    @Binding var draggedID: Int?
    @Binding var dropTargetID: Int?
    let onToggleCollapse: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if row.depth > 0 {
                Color.clear.frame(width: CGFloat(row.depth) * 12, height: 1)
            }
            disclosure
            NodeGlyph(node: row.node)
            nameView
            if isAnimated {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.fekthorAccent)
                    .help("This element is animated — open the timeline to edit")
            }
            Spacer(minLength: 4)
            eyeButton
            lockButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            selected ? .white.opacity(0.16) : .white.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isDropTarget ? Color.fekthorAccent.opacity(0.9) : .clear, lineWidth: 1.5)
        )
        .opacity(hidden ? 0.45 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(count: 2) { startRename() }
        .onTapGesture { select() }
        .onDrag {
            draggedID = row.id
            return NSItemProvider(object: String(row.id) as NSString)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: LayerDropDelegate(
                targetID: row.id, session: session,
                draggedID: $draggedID, dropTargetID: $dropTargetID))
    }

    /// The node carries an animation marker class (`fk-anim-*` binding).
    private var isAnimated: Bool {
        let targets = session.animationBindings.map(\.target)
        guard !targets.isEmpty else { return false }
        let classes = ClassTokens.list(row.node.nodeAttributes)
        return targets.contains { classes.contains($0) }
    }

    @ViewBuilder
    private var disclosure: some View {
        if row.isGroup {
            Button(action: onToggleCollapse) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand group" : "Collapse group")
        } else {
            Color.clear.frame(width: 12, height: 12)
        }
    }

    @ViewBuilder
    private var nameView: some View {
        if editingID == row.id {
            TextField(
                "name", text: $editText,
                onCommit: {
                    session.renameNode(row.id, to: editText)
                    editingID = nil
                }
            )
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .onExitCommand { editingID = nil }
        } else {
            Text(Self.displayName(row.node))
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var eyeButton: some View {
        Button {
            session.setNodeHidden(row.id, !hidden)
        } label: {
            Image(systemName: hidden ? "eye.slash" : "eye")
                .font(.system(size: 9))
                .foregroundStyle(hidden ? .primary : .secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hidden ? "Show (removes display: none)" : "Hide (sets display: none)")
    }

    private var lockButton: some View {
        Button {
            session.setNodeLocked(row.id, !locked)
        } label: {
            Image(systemName: locked ? "lock.fill" : "lock.open")
                .font(.system(size: 9))
                .foregroundStyle(locked ? .primary : .tertiary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(locked ? "Unlock" : "Lock (skipped by canvas selection)")
    }

    /// Row click: select (⇧/⌘ toggles membership). Locked rows do not
    /// select — locking means untouchable, in the panel too.
    private func select() {
        guard editingID != row.id else { return }
        guard !locked else {
            session.status = "“\(Self.displayName(row.node))” is locked."
            return
        }
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) || flags.contains(.command) {
            if session.selection.contains(row.id) {
                session.selection.remove(row.id)
            } else {
                session.selection.insert(row.id)
            }
        } else {
            session.selection = [row.id]
        }
        session.generation += 1
    }

    private func startRename() {
        editText = currentDataName
        editingID = row.id
    }

    /// The editable name: the data-name as authored (empty when derived).
    private var currentDataName: String {
        row.node.nodeAttributes.extras.first(where: { $0.name == "data-name" })?.value ?? ""
    }

    /// data-name attr → id attr → kind name.
    static func displayName(_ node: GraphicNode) -> String {
        let attrs = node.nodeAttributes
        if let name = attrs.extras.first(where: { $0.name == "data-name" })?.value,
            !name.isEmpty
        {
            return name
        }
        if let id = attrs.svgID, !id.isEmpty { return id }
        switch node {
        case .group: return "Group"
        case .raw: return "—"
        case .shape(let s):
            switch s.kind {
            case .path: return "Path"
            case .line: return "Line"
            case .polyline: return "Polyline"
            case .polygon: return "Polygon"
            case .rect: return "Rect"
            case .circle: return "Circle"
            case .ellipse: return "Ellipse"
            }
        }
    }
}

// MARK: - Drag reorder

/// Row drop target: highlights while hovered, and on drop moves the dragged
/// node to sit visually above this row (same sibling array; the session
/// rejects cross-parent drops with a status hint).
private struct LayerDropDelegate: DropDelegate {
    let targetID: Int
    let session: EditorSession
    @Binding var draggedID: Int?
    @Binding var dropTargetID: Int?

    func validateDrop(info: DropInfo) -> Bool {
        draggedID != nil && draggedID != targetID
    }

    func dropEntered(info: DropInfo) {
        if draggedID != targetID { dropTargetID = targetID }
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetID { dropTargetID = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedID = nil
            dropTargetID = nil
        }
        guard let moved = draggedID, moved != targetID else { return false }
        MainActor.assumeIsolated {
            session.reorderNode(moved, above: targetID)
        }
        return true
    }
}

// MARK: - Node thumbnail

/// A 16pt vector glyph of a node (shape or whole group): the same CGPath
/// geometry the canvas draws, fitted into the cell — cheap enough to draw
/// live, no bitmap cache needed.
private struct NodeGlyph: View {
    let node: GraphicNode

    var body: some View {
        Canvas { ctx, size in
            var items: [(path: CGPath, style: Style, lineLike: Bool)] = []
            Self.collect(node, transform: .identity, into: &items)
            var bounds = CGRect.null
            for item in items {
                bounds = bounds.union(item.path.boundingBoxOfPath)
            }
            guard !bounds.isNull, bounds.width.isFinite, bounds.height.isFinite else { return }
            let pad: CGFloat = 2.5
            let scale = min(
                (size.width - 2 * pad) / max(bounds.width, 0.001),
                (size.height - 2 * pad) / max(bounds.height, 0.001))
            let t = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(
                    CGAffineTransform(
                        translationX: (size.width - bounds.width * scale) / 2,
                        y: (size.height - bounds.height * scale) / 2))
            for item in items {
                let p = Path(item.path).applying(t)
                let style = item.style
                let fill = style.fill ?? (item.lineLike ? nil : PaintValue.color(r: 0, g: 0, b: 0))
                if let fill, let c = fill.renderColor {
                    let rule = FillStyle(
                        eoFill: {
                            if case .keyword("evenodd")? = style.value(of: "fill-rule") {
                                return true
                            }
                            return false
                        }())
                    ctx.fill(p, with: .color(Self.color(c)), style: rule)
                }
                if let stroke = style.stroke, let c = stroke.renderColor {
                    let width = max(0.6, min(2, (style.strokeWidth ?? 1) * scale))
                    ctx.stroke(p, with: .color(Self.color(c)), lineWidth: width)
                }
            }
        }
        .frame(width: 16, height: 16)
        .background(Color.fekthorWell, in: RoundedRectangle(cornerRadius: 3))
    }

    /// Every shape path under the node with its composed transform.
    private static func collect(
        _ node: GraphicNode, transform: CGAffineTransform,
        into items: inout [(path: CGPath, style: Style, lineLike: Bool)]
    ) {
        switch node {
        case .raw:
            break
        case .shape(let s):
            var t = transform
            if let m = s.transform { t = affine(m).concatenating(transform) }
            let base = CGPathBuilder.path(for: s.kind)
            var mt = t
            let path = base.copy(using: &mt) ?? base
            let lineLike: Bool
            switch s.kind {
            case .line, .polyline: lineLike = true
            default: lineLike = false
            }
            items.append((path, s.renderStyle, lineLike))
        case .group(let g):
            var t = transform
            if let m = g.transform { t = affine(m).concatenating(transform) }
            for child in g.children {
                collect(child, transform: t, into: &items)
            }
        }
    }

    private static func affine(_ t: TransformValue) -> CGAffineTransform {
        let m = t.matrix
        return CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5])
    }

    private static func color(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> Color {
        Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
}
