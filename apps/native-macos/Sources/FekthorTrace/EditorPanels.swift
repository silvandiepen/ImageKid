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
    case combine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "Fill"
        case .stroke: return "Stroke"
        case .opacity: return "Opacity"
        case .combine: return "Combine"
        }
    }

    var systemImage: String {
        switch self {
        case .fill: return "drop.fill"
        case .stroke: return "pencil.line"
        case .opacity: return "circle.lefthalf.filled"
        case .combine: return "square.on.square.intersection.dashed"
        }
    }

    /// First-run resting offset from the canvas's top-leading corner. The
    /// style column hugs the right of a minimum-size window; Opacity and
    /// Combine sit one column in so nothing overlaps.
    var defaultPosition: CGSize {
        switch self {
        case .fill: return CGSize(width: 660, height: 16)
        case .stroke: return CGSize(width: 660, height: 230)
        case .opacity: return CGSize(width: 400, height: 16)
        case .combine: return CGSize(width: 400, height: 180)
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
struct EditorPanelsLayer: View {
    @ObservedObject var session: EditorSession
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
