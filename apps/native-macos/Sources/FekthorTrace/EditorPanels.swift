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
    case opacity
    case corners
    case combine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "Fill"
        case .stroke: return "Stroke"
        case .opacity: return "Opacity"
        case .corners: return "Corners"
        case .combine: return "Combine"
        }
    }

    var systemImage: String {
        switch self {
        case .fill: return "drop.fill"
        case .stroke: return "pencil.line"
        case .opacity: return "circle.lefthalf.filled"
        case .corners: return "rectangle.roundedtop"
        case .combine: return "square.on.square.intersection.dashed"
        }
    }

    /// First-run resting offset from the canvas's top-leading corner. The
    /// style column hugs the right of a minimum-size window; Opacity,
    /// Corners and Combine sit one column in so nothing overlaps.
    var defaultPosition: CGSize {
        switch self {
        case .fill: return CGSize(width: 660, height: 16)
        case .stroke: return CGSize(width: 660, height: 230)
        case .opacity: return CGSize(width: 400, height: 16)
        case .corners: return CGSize(width: 400, height: 180)
        case .combine: return CGSize(width: 400, height: 380)
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
            if panels.visible.contains(.opacity) {
                palette(.opacity) { OpacityPanelContent(session: session) }
            }
            if panels.visible.contains(.corners) {
                palette(.corners) { CornersPanelContent(session: session) }
            }
            if panels.visible.contains(.combine) {
                palette(.combine) { CombinePanelContent(session: session) }
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
