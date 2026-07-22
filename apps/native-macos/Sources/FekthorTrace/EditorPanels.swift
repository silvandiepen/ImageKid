import AppKit
import FekthorKit
import ImageKidKit
import SwiftUI

/// The editor's floating palettes — Fill, Stroke, Opacity and Combine — using
/// the same ImageKid panel mechanic (`FloatingToolPanel` from ImageKidKit):
/// dark translucent chrome, dragged by the title bar anywhere over the canvas
/// (inside the window), closed from the chrome, toggled from the Panels menu
/// or the editor top bar. Visibility and per-panel positions persist in
/// UserDefaults.
enum EditorPanel: String, CaseIterable, Identifiable {
    case fill
    case stroke
    case swatches
    case opacity
    case corners
    case combine
    case align
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "Fill"
        case .stroke: return "Stroke"
        case .swatches: return "Swatches"
        case .opacity: return "Opacity"
        case .corners: return "Corners"
        case .combine: return "Combine"
        case .align: return "Align"
        case .history: return "History"
        }
    }

    var systemImage: String {
        switch self {
        case .fill: return "drop.fill"
        case .stroke: return "pencil.line"
        case .swatches: return "paintpalette"
        case .opacity: return "circle.lefthalf.filled"
        case .corners: return "rectangle.roundedtop"
        case .combine: return "square.on.square.intersection.dashed"
        case .align: return "align.horizontal.left"
        case .history: return "clock.arrow.circlepath"
        }
    }

    /// First-run resting offset from the canvas's top-leading corner. The
    /// style column hugs the right of a minimum-size window; Opacity,
    /// Corners and Combine sit one column in; Swatches, Align and History
    /// stack down the leading edge so nothing overlaps.
    var defaultPosition: CGSize {
        switch self {
        case .fill: return CGSize(width: 660, height: 16)
        case .stroke: return CGSize(width: 660, height: 230)
        case .swatches: return CGSize(width: 16, height: 16)
        case .opacity: return CGSize(width: 400, height: 16)
        case .corners: return CGSize(width: 400, height: 180)
        case .combine: return CGSize(width: 400, height: 380)
        case .align: return CGSize(width: 16, height: 240)
        case .history: return CGSize(width: 16, height: 400)
        }
    }
}

/// Shared, persisted panel state: which palettes are open and where each one
/// rests. A singleton (like `MenuState`) so the Panels menu, the editor top
/// bar and the overlay layer all drive the same state.
@MainActor
final class EditorPanelsState: ObservableObject {
    static let shared = EditorPanelsState()

    /// Panels currently shown (while an editor is open).
    @Published var visible: Set<EditorPanel> {
        didSet {
            UserDefaults.standard.set(
                visible.map(\.rawValue).sorted(), forKey: Self.visibleKey)
        }
    }

    /// Per-panel offsets from the canvas's top-leading corner.
    @Published private var positions: [EditorPanel: CGSize]

    private static let visibleKey = "fekthor.panels.visible"
    private static func positionKey(_ panel: EditorPanel) -> String {
        "fekthor.panel.\(panel.rawValue).position"
    }

    private init() {
        if let raw = UserDefaults.standard.array(forKey: Self.visibleKey) as? [String] {
            visible = Set(raw.compactMap(EditorPanel.init(rawValue:)))
        } else {
            visible = Set(EditorPanel.allCases)
        }
        var loaded: [EditorPanel: CGSize] = [:]
        for panel in EditorPanel.allCases {
            if let pair = UserDefaults.standard.array(
                forKey: Self.positionKey(panel)) as? [Double], pair.count == 2
            {
                loaded[panel] = CGSize(width: pair[0], height: pair[1])
            }
        }
        positions = loaded
    }

    func position(_ panel: EditorPanel) -> CGSize {
        positions[panel] ?? panel.defaultPosition
    }

    func setPosition(_ panel: EditorPanel, to position: CGSize) {
        positions[panel] = position
        UserDefaults.standard.set(
            [position.width, position.height], forKey: Self.positionKey(panel))
    }

    func positionBinding(_ panel: EditorPanel) -> Binding<CGSize> {
        Binding(
            get: { self.position(panel) },
            set: { self.setPosition(panel, to: $0) })
    }

    func toggleBinding(_ panel: EditorPanel) -> Binding<Bool> {
        Binding(
            get: { self.visible.contains(panel) },
            set: { shown in
                if shown {
                    self.visible.insert(panel)
                } else {
                    self.visible.remove(panel)
                }
            })
    }
}

/// The overlay hosting every open palette above the editor canvas. Drag ends
/// snap to a 20pt grid and clamp inside the top-leading corner, matching the
/// ImageKid dock behaviour.
///
/// The session is deliberately NOT observed here: the palette contents each
/// observe it themselves, and observing it at the layer level rebuilt every
/// floating panel on every session publish (generation bumps per canvas drag
/// event, status ticks) — mid-drag rebuilds that made the panel drags
/// stutter instead of tracking the pointer freely. The layer re-evaluates
/// only when the panel state itself (visibility, resting positions) changes.
struct EditorPanelsLayer: View {
    let session: EditorSession
    /// Plain reference (NOT observed at this level — same discipline as the
    /// editor session): only the Swatches palette content observes it.
    let workspace: WorkspaceSession
    @ObservedObject private var panels = EditorPanelsState.shared

    private static let snapStep: CGFloat = 20
    private static let panelWidth: CGFloat = 240

    var body: some View {
        ZStack(alignment: .topLeading) {
            if panels.visible.contains(.fill) {
                palette(.fill) { FillPanelContent(session: session) }
            }
            if panels.visible.contains(.stroke) {
                palette(.stroke) { StrokePanelContent(session: session) }
            }
            if panels.visible.contains(.swatches) {
                palette(.swatches) {
                    SwatchesPanelContent(session: session, workspace: workspace)
                }
            }
            if panels.visible.contains(.opacity) {
                palette(.opacity) { OpacityPanelContent(session: session) }
            }
            if panels.visible.contains(.corners) {
                palette(.corners) { CornersPanelContent(session: session) }
            }
            if panels.visible.contains(.combine) {
                palette(.combine) { CombinePanelContent(session: session) }
            }
            if panels.visible.contains(.align) {
                palette(.align) { AlignPanelContent(session: session) }
            }
            if panels.visible.contains(.history) {
                palette(.history) { HistoryPanelContent(session: session) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func palette(
        _ panel: EditorPanel, @ViewBuilder content: () -> some View
    ) -> some View {
        FloatingToolPanel(
            title: panel.title,
            systemImage: panel.systemImage,
            width: Self.panelWidth,
            offset: panels.positionBinding(panel),
            onClose: { panels.visible.remove(panel) },
            snapStep: Self.snapStep,
            cornerRadius: 18
        ) {
            content()
        }
        // Explicit stable identity: the free drag lives in @GestureState,
        // which survives only as long as the panel view's identity does.
        .id(panel)
    }
}

// MARK: - Swatches palette

/// Colour swatches: the WORKSPACE swatches first (shared through the
/// workfile — editable: + adds the current fill colour, right-click offers
/// Set as Fill / Set as Stroke / Delete), then the unique plain colours the
/// open document already uses (read-only). Click applies a swatch as the
/// selection's fill (or the drawing style when nothing is selected);
/// ⌥-click applies it as the stroke. Each apply is ONE undo step.
struct SwatchesPanelContent: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var workspace: WorkspaceSession

    private var workspaceSwatches: [String] { workspace.settings.swatches ?? [] }

    /// Unique plain colours used by the document's shapes, in document
    /// order (each shape's fill before its stroke).
    private var documentColors: [String] {
        var seen: Set<String> = []
        var out: [String] = []
        func add(_ paint: PaintValue?) {
            guard case .color(let r, let g, let b)? = paint else { return }
            let hex = String(format: "#%02x%02x%02x", r, g, b)
            if seen.insert(hex).inserted { out.append(hex) }
        }
        func walk(_ nodes: [GraphicNode]) {
            for node in nodes {
                switch node {
                case .raw: continue
                case .group(let g): walk(g.children)
                case .shape(let s):
                    let style = s.effectiveStyle
                    add(style.fill)
                    add(style.stroke)
                }
            }
        }
        walk(session.document.nodes)
        return out
    }

    /// The colour "+" adds: the current fill when it is a plain colour,
    /// else the current stroke. nil (no plain colour anywhere) disables +.
    private var addableHex: String? {
        let selection = StyleSelection(session: session)
        if case .color(let r, let g, let b) = selection.summary(of: { $0.fill }) {
            return String(format: "#%02x%02x%02x", r, g, b)
        }
        if case .color(let r, let g, let b) = selection.summary(of: { $0.stroke }) {
            return String(format: "#%02x%02x%02x", r, g, b)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if workspace.workspace != nil {
                    addButton
                }
            }
            if workspace.workspace == nil {
                Text("Open a workspace to keep shared swatches.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if workspaceSwatches.isEmpty {
                Text("No swatches yet — + adds the current colour.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                swatchGrid(workspaceSwatches, editable: true)
            }
            Divider()
            Text("In this document")
                .font(.caption)
                .foregroundStyle(.secondary)
            if documentColors.isEmpty {
                Text("No plain colours in use.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                swatchGrid(documentColors, editable: false)
            }
            Text("Click: fill · ⌥-click: stroke")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var addButton: some View {
        Button {
            addSwatch()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(addableHex == nil)
        .opacity(addableHex == nil ? 0.4 : 1)
        .help("Add the current fill colour (or stroke, when the fill is not a plain colour)")
    }

    private func swatchGrid(_ hexes: [String], editable: Bool) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 22, maximum: 22), spacing: 6)],
            alignment: .leading, spacing: 6
        ) {
            ForEach(hexes, id: \.self) { hex in
                swatch(hex, editable: editable)
            }
        }
    }

    private func swatch(_ hex: String, editable: Bool) -> some View {
        Button {
            apply(hex, asStroke: NSEvent.modifierFlags.contains(.option))
        } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(swatchColor(hex))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("\(hex) — click: fill · ⌥-click: stroke")
        .contextMenu {
            Button("Set as Fill") { apply(hex, asStroke: false) }
            Button("Set as Stroke") { apply(hex, asStroke: true) }
            if editable {
                Divider()
                Button("Delete", role: .destructive) { removeSwatch(hex) }
            }
        }
    }

    private func swatchColor(_ hex: String) -> Color {
        guard let c = PaintValue.parseHex(hex) else { return .black }
        return Color(
            red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    /// Apply the swatch to the selection (or the drawing style when nothing
    /// is selected) — one undo step per click, never coalesced.
    private func apply(_ hex: String, asStroke: Bool) {
        guard let c = PaintValue.parseHex(hex) else { return }
        let paint = PaintValue.color(r: c.r, g: c.g, b: c.b)
        if asStroke {
            session.editSelectionStyle("stroke", label: "Stroke colour") { $0.stroke = paint }
        } else {
            session.editSelectionStyle("fill", label: "Fill colour") { $0.fill = paint }
        }
        session.endStyleEdit()
    }

    private func addSwatch() {
        guard let hex = addableHex else { return }
        workspace.updateSettings { workfile in
            var list = workfile.swatches ?? []
            guard !list.contains(hex) else { return }
            list.append(hex)
            workfile.swatches = list
        }
    }

    private func removeSwatch(_ hex: String) {
        workspace.updateSettings { workfile in
            workfile.swatches?.removeAll { $0 == hex }
        }
    }
}

// MARK: - Align palette

/// Illustrator's Align palette over the existing engine ops: six align
/// buttons (left / centre / right, top / middle / bottom) and two
/// distribute buttons (H / V). 2+ nodes align to their collective bounds;
/// a single node aligns to the artboard (the tooltips say so); distribute
/// needs 3+. Disabled states match the Object ▸ Align menu.
struct AlignPanelContent: View {
    @ObservedObject var session: EditorSession

    private var canAlign: Bool { !session.selection.isEmpty }
    private var canDistribute: Bool { session.selection.count >= 3 }
    private var single: Bool { session.selection.count == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Align objects")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                alignButton(.left, "align.horizontal.left", "Align Left")
                alignButton(.centerX, "align.horizontal.center", "Align Center")
                alignButton(.right, "align.horizontal.right", "Align Right")
                alignButton(.top, "align.vertical.top", "Align Top")
                alignButton(.centerY, "align.vertical.center", "Align Middle")
                alignButton(.bottom, "align.vertical.bottom", "Align Bottom")
            }
            Text("Distribute")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                distributeButton(.horizontal, "distribute.horizontal.center", "Distribute Horizontally")
                distributeButton(.vertical, "distribute.vertical.center", "Distribute Vertically")
            }
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var hint: String {
        if !canAlign { return "Select something to align" }
        if single { return "One node aligns to the artboard" }
        if !canDistribute { return "Distribute needs three or more nodes" }
        return " "
    }

    private func alignButton(_ edge: AlignEdge, _ symbol: String, _ name: String) -> some View {
        Button {
            session.alignSelection(edge)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 26)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!canAlign)
        .opacity(canAlign ? 1 : 0.4)
        .help(single ? "\(name) — a single node aligns to the artboard" : name)
    }

    private func distributeButton(
        _ axis: DistributeAxis, _ symbol: String, _ name: String
    ) -> some View {
        Button {
            session.distributeSelection(axis)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 45, height: 26)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!canDistribute)
        .opacity(canDistribute ? 1 : 0.4)
        .help("\(name) (equalise the gaps between three or more nodes)")
    }
}

// MARK: - History palette

/// The labelled undo stack, newest-first: "Current" on top, then every
/// snapshot (each labelled with the operation that FOLLOWED it). Clicking
/// an older entry reverts to that snapshot — i.e. to the document as it was
/// BEFORE that entry's operation ran. The current state is pushed as a
/// "Revert" entry first, so clicking that entry afterwards brings the
/// reverted-away state back (redo by history); the stack keeps its 50 cap.
struct HistoryPanelContent: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        // Reading `generation`/`canUndo` via @ObservedObject keeps the list
        // fresh: every stack change rides one of those publishes.
        let entries = Array(session.history.reversed())
        VStack(alignment: .leading, spacing: 8) {
            Text("Click a step to revert to the state before it")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 2) {
                    currentRow
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            }
            .frame(maxHeight: 240)
            if entries.isEmpty {
                Text("No edits yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currentRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
            Text("Current")
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private func row(_ entry: EditorSession.HistoryEntry) -> some View {
        Button {
            session.revert(toHistoryID: entry.id)
        } label: {
            HStack {
                Text(entry.label)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Revert to the document as it was before “\(entry.label)”")
    }
}

// MARK: - Corners palette

/// Corner radius for rectangle selections. Linked (the default), one radius
/// edits every corner and the node stays a native `.rect` (the radius lands
/// in rx) so it round-trips; the chain button decouples the corners into
/// four fields, and the first per-corner edit converts the rect to a
/// `.path` via `CornerRadius.roundedRectPath` — per-corner rounding has no
/// rect form. Anything but a rect selection shows a hint (future: live
/// corner editing on paths).
struct CornersPanelContent: View {
    @ObservedObject var session: EditorSession

    @State private var linked = true
    @State private var uniform: Double = 0
    @State private var topLeft: Double = 0
    @State private var topRight: Double = 0
    @State private var bottomRight: Double = 0
    @State private var bottomLeft: Double = 0
    /// Rect geometry captured when the chain broke — the nodes may be
    /// `.path` right after, so per-corner edits rebuild from these.
    @State private var decoupled: [EditorSession.CornerRect] = []

    private struct RectSelection {
        var rect: EditorSession.CornerRect
        var radius: Double
    }

    /// The selected shapes that are native rects, with their effective
    /// uniform radius (rx/ry defaulting, clamped like the renderer).
    private var selectedRects: [RectSelection] {
        session.selection.sorted().compactMap { id in
            guard let shape = session.document.firstShape(id: id),
                case .rect(let x, let y, let w, let h, let rx, let ry) = shape.kind
            else { return nil }
            return RectSelection(
                rect: .init(id: id, x: x, y: y, width: w, height: h),
                radius: min(rx ?? ry ?? 0, min(w, h) / 2))
        }
    }

    private var allRects: Bool {
        !session.selection.isEmpty && selectedRects.count == session.selection.count
    }

    /// Linked mode needs a pure-rect selection; decoupled mode stays alive
    /// on the SAME selection even after the nodes converted to paths.
    private var active: Bool {
        linked
            ? allRects
            : !decoupled.isEmpty && Set(decoupled.map(\.id)) == session.selection
    }

    private var maxRadius: Double {
        let geoms = linked ? selectedRects.map(\.rect) : decoupled
        return max(1, geoms.map { min($0.width, $0.height) / 2 }.min() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if active {
                HStack {
                    Text(headerText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    linkButton
                }
                if linked {
                    uniformRow
                } else {
                    cornerGrid
                    Text("Per-corner radii — the rect becomes a path")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select a rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { syncUniform() }
        .onChange(of: session.selection) { _, _ in
            session.endStyleEdit()
            linked = true
            decoupled = []
            syncUniform()
        }
        .onChange(of: session.generation) { _, _ in
            if linked { syncUniform() }
        }
    }

    private var headerText: String {
        let count = linked ? selectedRects.count : decoupled.count
        return count == 1 ? "Rectangle" : "\(count) rectangles"
    }

    private var linkButton: some View {
        Button {
            toggleLink()
        } label: {
            Image(systemName: "link")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(
                    .white.opacity(linked ? 0.28 : 0.08),
                    in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(linked ? "Decouple corners (one radius each)" : "Link corners (one radius)")
    }

    private var uniformRow: some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { uniform },
                    set: { v in
                        uniform = v
                        session.setRectRadius(v)
                    }),
                in: 0...maxRadius,
                onEditingChanged: { editing in
                    if !editing { session.endStyleEdit() }
                }
            )
            TextField(
                "0",
                value: Binding(
                    get: { uniform },
                    set: { v in
                        uniform = max(0, min(v, maxRadius))
                        session.setRectRadius(uniform)
                        session.endStyleEdit()
                    }),
                format: .number.precision(.fractionLength(0...2))
            )
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospaced())
            .frame(width: 52)
        }
    }

    private var cornerGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                cornerField("TL", $topLeft)
                cornerField("TR", $topRight)
            }
            HStack(spacing: 8) {
                cornerField("BL", $bottomLeft)
                cornerField("BR", $bottomRight)
            }
        }
    }

    private func cornerField(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            TextField(
                "0",
                value: Binding(
                    get: { value.wrappedValue },
                    set: { v in
                        value.wrappedValue = max(0, v)
                        applyPerCorner()
                        session.endStyleEdit()
                    }),
                format: .number.precision(.fractionLength(0...2))
            )
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospaced())
        }
    }

    private func toggleLink() {
        if linked {
            // Break the chain: remember the rect geometry (per-corner edits
            // rebuild from it) and seed all four fields with the current
            // radius. Nothing mutates until a corner is actually edited.
            let rects = selectedRects
            decoupled = rects.map(\.rect)
            let seed = rects.first?.radius ?? 0
            topLeft = seed
            topRight = seed
            bottomRight = seed
            bottomLeft = seed
            linked = false
        } else {
            // Re-link: nodes that converted to paths come back as native
            // rects with one uniform radius; untouched rects just relink.
            let converted = decoupled.contains { rect in
                if case .rect = session.document.firstShape(id: rect.id)?.kind {
                    return false
                }
                return true
            }
            if converted {
                session.relinkRectRadius(rects: decoupled, radius: topLeft)
            }
            uniform = max(0, min(topLeft, maxRadius))
            decoupled = []
            linked = true
            syncUniform()
        }
    }

    private func applyPerCorner() {
        guard !decoupled.isEmpty else { return }
        session.setRectPerCornerRadii(
            rects: decoupled, topLeft: topLeft, topRight: topRight,
            bottomRight: bottomRight, bottomLeft: bottomLeft)
    }

    private func syncUniform() {
        uniform = selectedRects.first?.radius ?? 0
    }
}

// MARK: - Combine (Pathfinder) panel

/// Illustrator's Pathfinder shape modes, under a friendlier name: one row of
/// glyph buttons — Unite, Minus Front, Intersect, Exclude — over the same
/// boolean ops the Object ▸ Path menu drives (`EditorSession.combineSelection`).
struct CombinePanelContent: View {
    @ObservedObject var session: EditorSession

    private var canCombine: Bool { session.selection.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shape modes")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                opButton(.union, "Unite")
                opButton(.subtract, "Minus Front")
                opButton(.intersect, "Intersect")
                opButton(.exclude, "Exclude")
            }
            Text(canCombine ? " " : "Select two or more shapes")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func opButton(_ op: BoolOp, _ name: String) -> some View {
        Button {
            session.combineSelection(op)
        } label: {
            CombineOpGlyph(op: op)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!canCombine)
        .opacity(canCombine ? 1 : 0.4)
        .help(name)
    }
}

/// A Pathfinder-style glyph: two overlapping rounded squares whose filled
/// region is the op's result (outlines always drawn), recognizable at a
/// glance like Illustrator's shape-mode row.
private struct CombineOpGlyph: View {
    let op: BoolOp

    private var rectA: Path {
        Path(roundedRect: CGRect(x: 0.5, y: 0.5, width: 13, height: 13), cornerRadius: 3)
    }
    private var rectB: Path {
        Path(roundedRect: CGRect(x: 8.5, y: 8.5, width: 13, height: 13), cornerRadius: 3)
    }
    private var both: Path {
        var p = rectA
        p.addPath(rectB)
        return p
    }

    var body: some View {
        ZStack {
            both.stroke(Color.white.opacity(0.45), lineWidth: 1)
            filled
        }
        .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private var filled: some View {
        switch op {
        case .union:
            both.fill(Color.white)
        case .subtract:
            ZStack {
                rectA.fill(Color.white)
                rectB.fill(Color.black).blendMode(.destinationOut)
            }
            .compositingGroup()
        case .intersect:
            rectA.fill(Color.white)
                .mask { rectB.fill(Color.black) }
        case .exclude:
            both.fill(Color.white, style: FillStyle(eoFill: true))
        }
    }
}
