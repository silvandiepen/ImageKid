import AppKit
import FekthorKit
import ImageKidKit
import SwiftUI

/// The editor's floating palettes — Fill, Stroke, Opacity and Combine — using
/// the same ImageKid panel mechanic (`FloatingToolPanel` from ImageKidKit):
/// dark translucent chrome, dragged by the title bar anywhere over the canvas
/// (inside the window), toggled from an always-visible rail of small buttons
/// down the top-left (ImageKid's `PanelDockRail` look), the Panels menu or
/// the editor top bar. Palettes stick magnetically when one is dropped onto
/// another's bottom edge (shared `PanelStacks` model) and flush onto the
/// left/right dock edge; positions persist edge-relative so right-docked
/// palettes follow the right edge across window resizes, and every palette
/// is kept reachable inside the dock. Visibility, minimized palettes, stacks
/// and per-panel anchors persist in UserDefaults.
enum EditorPanel: String, CaseIterable, Identifiable {
    case fill
    case stroke
    case swatches
    case styles
    case opacity
    case corners
    case transform
    case combine
    case align
    case history
    case layers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "Fill"
        case .stroke: return "Stroke"
        case .swatches: return "Swatches"
        case .styles: return "Styles"
        case .opacity: return "Opacity"
        case .corners: return "Corners"
        case .transform: return "Transform"
        case .combine: return "Combine"
        case .align: return "Align"
        case .history: return "History"
        case .layers: return "Layers"
        }
    }

    var systemImage: String {
        switch self {
        case .fill: return "drop.fill"
        case .stroke: return "pencil.line"
        case .swatches: return "paintpalette"
        case .styles: return "paintbrush.pointed"
        case .opacity: return "circle.lefthalf.filled"
        case .corners: return "rectangle.roundedtop"
        case .transform: return "skew"
        case .combine: return "square.on.square.intersection.dashed"
        case .align: return "align.horizontal.left"
        case .history: return "clock.arrow.circlepath"
        case .layers: return "square.3.stack.3d"
        }
    }

    /// The floating palettes' shared width (FloatingToolPanel `width`).
    static let panelWidth: CGFloat = 240

    /// The style column docks to the RIGHT edge, everything else to the
    /// LEFT — each column stacked top-down with 16pt gaps using the
    /// estimated heights below.
    private static let rightColumn: [EditorPanel] = [
        .fill, .stroke, .opacity, .corners, .transform, .combine,
    ]
    private static let leftColumn: [EditorPanel] = [
        .layers, .swatches, .styles, .align, .history,
    ]

    /// Rough on-screen height (chrome + content), used to stack the default
    /// columns without overlaps and as the size fallback while a freshly
    /// opened palette is still unmeasured — not pixel-perfect by design.
    var estimatedHeight: CGFloat {
        switch self {
        case .fill: return 260
        case .stroke: return 320
        case .opacity: return 140
        case .corners: return 180
        case .transform: return 280
        case .combine: return 150
        case .layers: return 360
        case .swatches: return 260
        case .styles: return 240
        case .align: return 200
        case .history: return 200
        }
    }

    /// First-run resting offset from the canvas's top-leading corner,
    /// docked to the window edges: the style panels (Fill, Stroke, Opacity,
    /// Corners, Combine) stack down the RIGHT edge; Layers, Swatches,
    /// Styles, Align and History stack down the LEFT. Degenerate canvas
    /// sizes fall back to fixed offsets so panels never dock off-screen.
    func defaultPosition(in size: CGSize) -> CGSize {
        guard size.width >= 600 else { return fallbackPosition }
        if let index = Self.rightColumn.firstIndex(of: self) {
            return CGSize(
                width: size.width - Self.panelWidth - 16,
                height: Self.stackedY(Self.rightColumn, upTo: index))
        }
        let index = Self.leftColumn.firstIndex(of: self) ?? 0
        return CGSize(width: 16, height: Self.stackedY(Self.leftColumn, upTo: index))
    }

    /// 16pt top inset, then each preceding panel's estimated height + gap.
    private static func stackedY(_ column: [EditorPanel], upTo index: Int) -> CGFloat {
        column.prefix(index).reduce(16) { $0 + $1.estimatedHeight + 16 }
    }

    /// Pre-docking constants, kept as the degenerate-size fallback.
    private var fallbackPosition: CGSize {
        switch self {
        case .fill: return CGSize(width: 660, height: 16)
        case .stroke: return CGSize(width: 660, height: 250)
        case .layers: return CGSize(width: 16, height: 16)
        case .swatches: return CGSize(width: 16, height: 420)
        case .styles: return CGSize(width: 280, height: 16)
        case .opacity: return CGSize(width: 660, height: 560)
        case .corners: return CGSize(width: 400, height: 300)
        case .transform: return CGSize(width: 400, height: 380)
        case .combine: return CGSize(width: 400, height: 480)
        case .align: return CGSize(width: 280, height: 420)
        case .history: return CGSize(width: 400, height: 16)
        }
    }

    /// First-run size for panels that opt into FloatingToolPanel's resizable
    /// mode (only Layers today — a node tree wants height).
    var defaultSize: CGSize {
        switch self {
        case .layers: return CGSize(width: 240, height: 360)
        default: return .zero
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
            AppDefaults.store.set(
                visible.map(\.rawValue).sorted(), forKey: Self.visibleKey)
        }
    }

    /// Palettes collapsed out of the way (still in `visible` — their rail
    /// button stays highlighted and a click restores them where they were).
    @Published var minimized: Set<EditorPanel> {
        didSet {
            AppDefaults.store.set(
                minimized.map(\.rawValue).sorted(), forKey: Self.minimizedKey)
        }
    }

    /// Which palettes are magnetically stuck together, ordered top → bottom
    /// (shared stacking model from ImageKidKit, keyed by rawValue).
    @Published var stacks: PanelStacks {
        didSet {
            guard let data = try? JSONEncoder().encode(stacks) else { return }
            AppDefaults.store.set(data, forKey: Self.stacksKey)
        }
    }

    /// Edge-anchored resting spot: which dock side the palette belongs to
    /// (its centre against the dock midpoint), the horizontal offset from
    /// that side's edge (leading edge from the left, trailing edge from the
    /// right — 0 means flush) and the absolute y. Right-side palettes
    /// therefore hug the right edge across window resizes instead of being
    /// stranded mid-canvas.
    struct Anchor: Codable, Equatable {
        var side: PanelDockSide
        var offset: CGFloat
        var y: CGFloat
    }

    /// Per-panel edge anchors (v4); nil = never moved, docked default.
    @Published private var anchors: [EditorPanel: Anchor]
    /// v3 absolute offsets waiting for the first real dock size — side and
    /// edge offset need the dock width, so they convert lazily in
    /// `migrateLegacyPositions(in:)` and serve as-is until then.
    private var legacyPositions: [EditorPanel: CGSize]
    /// Per-panel sizes for the resizable panels (Layers).
    @Published private var sizes: [EditorPanel: CGSize]

    /// Palettes freshly opened (hidden → shown) that still need a spot in
    /// the dock columns. The layer drains this — placement runs against the
    /// OPEN palettes' measured frames, which the state cannot see. Never
    /// persisted.
    @Published var needsPlacement: Set<EditorPanel> = []

    // v3 keys: v1 shipped every palette open in an overlapping pile, v2
    // scattered them over fixed offsets; v3 re-defaults everyone once into
    // the edge-docked layout without touching other preferences. Positions
    // alone moved on to v4 (edge-relative anchors) — v3 absolute positions
    // migrate on the first real layout pass and their keys are removed.
    private static let visibleKey = "fekthor.panels.visible.v3"
    private static let minimizedKey = "fekthor.panels.minimized.v3"
    private static let stacksKey = "fekthor.panels.stacks.v3"
    private static func legacyPositionKey(_ panel: EditorPanel) -> String {
        "fekthor.panel.\(panel.rawValue).position.v3"
    }
    private static func anchorKey(_ panel: EditorPanel) -> String {
        "fekthor.panel.\(panel.rawValue).anchor.v4"
    }
    private static func sizeKey(_ panel: EditorPanel) -> String {
        "fekthor.panel.\(panel.rawValue).size.v3"
    }

    /// First-run set: the daily-driver palettes. Everything else is one
    /// click away in the Panels menu — ten open palettes bury the canvas.
    private static let defaultVisible: Set<EditorPanel> = [.fill, .stroke, .layers]

    private init() {
        let loadedVisible: Set<EditorPanel>
        if let raw = AppDefaults.store.array(forKey: Self.visibleKey) as? [String] {
            loadedVisible = Set(raw.compactMap(EditorPanel.init(rawValue:)))
        } else {
            loadedVisible = Self.defaultVisible
        }
        visible = loadedVisible
        let loadedMinimized: Set<EditorPanel>
        if let raw = AppDefaults.store.array(forKey: Self.minimizedKey) as? [String] {
            loadedMinimized = Set(raw.compactMap(EditorPanel.init(rawValue:)))
        } else {
            loadedMinimized = []
        }
        minimized = loadedMinimized
        var loadedStacks = PanelStacks()
        if let data = AppDefaults.store.data(forKey: Self.stacksKey),
            let decoded = try? JSONDecoder().decode(PanelStacks.self, from: data)
        {
            loadedStacks = decoded
            // A palette that is unknown, hidden or minimized cannot stay stuck.
            for key in loadedStacks.stacks.flatMap({ $0 }) {
                guard let panel = EditorPanel(rawValue: key),
                    loadedVisible.contains(panel), !loadedMinimized.contains(panel)
                else {
                    loadedStacks.detach(key)
                    continue
                }
            }
        }
        stacks = loadedStacks
        var loadedAnchors: [EditorPanel: Anchor] = [:]
        var loadedLegacy: [EditorPanel: CGSize] = [:]
        var loadedSizes: [EditorPanel: CGSize] = [:]
        for panel in EditorPanel.allCases {
            if let data = AppDefaults.store.data(forKey: Self.anchorKey(panel)),
                let anchor = try? JSONDecoder().decode(Anchor.self, from: data)
            {
                loadedAnchors[panel] = anchor
            } else if let pair = AppDefaults.store.array(
                forKey: Self.legacyPositionKey(panel)) as? [Double], pair.count == 2
            {
                loadedLegacy[panel] = CGSize(width: pair[0], height: pair[1])
            }
            if let pair = AppDefaults.store.array(
                forKey: Self.sizeKey(panel)) as? [Double], pair.count == 2
            {
                loadedSizes[panel] = CGSize(width: pair[0], height: pair[1])
            }
        }
        anchors = loadedAnchors
        legacyPositions = loadedLegacy
        sizes = loadedSizes
    }

    /// The palette's chrome width — fixed for everything but the resizable
    /// Layers palette (anchor resolution needs it to hold a trailing edge).
    private func panelWidth(_ panel: EditorPanel) -> CGFloat {
        panel == .layers ? size(.layers).width : EditorPanel.panelWidth
    }

    /// Where the palette rests in the CURRENT dock: the stored anchor
    /// resolved against this dock width (right-side palettes ride the right
    /// edge across window resizes) and clamped so at least 80pt of the
    /// palette — and its whole header bar — stay inside the dock. Unmigrated
    /// v3 spots serve absolute until the first real dock size arrives;
    /// palettes never moved take the edge-docked default.
    func position(_ panel: EditorPanel, in dock: CGSize) -> CGSize {
        if let anchor = anchors[panel] {
            let width = panelWidth(panel)
            guard dock.width > 0 else {
                // Transient zero-size layout pass — nothing sane to resolve
                // a right anchor against, and nothing visible to clamp for.
                return CGSize(
                    width: anchor.side == .left ? anchor.offset : 0, height: anchor.y)
            }
            let point = PanelPlacement.clamped(
                CGPoint(
                    x: PanelPlacement.resolveX(
                        side: anchor.side, edgeOffset: anchor.offset,
                        panelWidth: width, dockWidth: dock.width),
                    y: anchor.y),
                panelSize: CGSize(width: width, height: panel.estimatedHeight),
                dock: dock)
            return CGSize(width: point.x, height: point.y)
        }
        if let legacy = legacyPositions[panel] { return legacy }
        return panel.defaultPosition(in: dock)
    }

    /// Store a resting spot as an edge anchor: the side comes from the
    /// palette centre against the dock midpoint, the offset from that side's
    /// edge. A degenerate dock (zero-size layout pass) stores left/absolute
    /// so nothing is lost.
    func setPosition(_ panel: EditorPanel, to position: CGSize, in dock: CGSize) {
        let width = panelWidth(panel)
        let side: PanelDockSide =
            dock.width > 0
            ? PanelPlacement.side(
                ofPanelAt: position.width, panelWidth: width, dockWidth: dock.width)
            : .left
        let anchor = Anchor(
            side: side,
            offset: PanelPlacement.edgeOffset(
                forPanelAt: position.width, side: side, panelWidth: width,
                dockWidth: dock.width),
            y: position.height)
        anchors[panel] = anchor
        legacyPositions[panel] = nil
        if let data = try? JSONEncoder().encode(anchor) {
            AppDefaults.store.set(data, forKey: Self.anchorKey(panel))
        }
        AppDefaults.store.removeObject(forKey: Self.legacyPositionKey(panel))
    }

    /// One-time v3 → v4 conversion, run by the layer once a believable dock
    /// size is known: side and edge offset need the dock width — deriving
    /// them from a degenerate width would misfile every palette as
    /// left-docked. Until then the absolute v3 values serve unchanged.
    func migrateLegacyPositions(in dock: CGSize) {
        guard dock.width >= 300, !legacyPositions.isEmpty else { return }
        for (panel, position) in legacyPositions {
            setPosition(panel, to: position, in: dock)
        }
        legacyPositions = [:]
    }

    func size(_ panel: EditorPanel) -> CGSize {
        sizes[panel] ?? panel.defaultSize
    }

    func setSize(_ panel: EditorPanel, to size: CGSize) {
        sizes[panel] = size
        AppDefaults.store.set(
            [size.width, size.height], forKey: Self.sizeKey(panel))
    }

    func sizeBinding(_ panel: EditorPanel) -> Binding<CGSize> {
        Binding(
            get: { self.size(panel) },
            set: { self.setSize(panel, to: $0) })
    }

    /// Shown as a full palette (visible and not collapsed to a chip).
    func isExpanded(_ panel: EditorPanel) -> Bool {
        visible.contains(panel) && !minimized.contains(panel)
    }

    /// Chrome minimize: collapse the palette out of the way. A stacked
    /// palette detaches first — its followers close up, and a collapsed
    /// palette can't be a stick target. Its (still highlighted) rail button
    /// or the Panels menu restores it where it was.
    func minimize(_ panel: EditorPanel) {
        stacks.detach(panel.rawValue)
        minimized.insert(panel)
    }

    /// Un-minimizing restores the palette where it was; opening it fresh
    /// (hidden → shown) queues it for a free slot in the dock columns
    /// instead of whatever stale spot is stored (the layer places it).
    func restore(_ panel: EditorPanel) {
        if !visible.contains(panel) { needsPlacement.insert(panel) }
        visible.insert(panel)
        minimized.remove(panel)
    }

    /// Menu hide: fully closes the palette (and forgets any stick).
    func hide(_ panel: EditorPanel) {
        stacks.detach(panel.rawValue)
        minimized.remove(panel)
        visible.remove(panel)
        needsPlacement.remove(panel)
    }

    /// Rail button behaviour (ImageKid's `PanelDockModel.railToggle`): show
    /// if hidden, restore if minimized, hide if open.
    func railToggle(_ panel: EditorPanel) {
        if !visible.contains(panel) {
            restore(panel)
        } else if minimized.contains(panel) {
            minimized.remove(panel)
        } else {
            hide(panel)
        }
    }

    /// Drain the palettes waiting for an opening spot, in menu order.
    func takePendingPlacement() -> [EditorPanel] {
        guard !needsPlacement.isEmpty else { return [] }
        let pending = needsPlacement
        needsPlacement = []
        return EditorPanel.allCases.filter(pending.contains)
    }

    /// Menu semantics: checked = expanded on the canvas; toggling on
    /// restores a minimized palette, toggling off hides it entirely.
    func toggleBinding(_ panel: EditorPanel) -> Binding<Bool> {
        Binding(
            get: { self.isExpanded(panel) },
            set: { shown in
                if shown {
                    self.restore(panel)
                } else {
                    self.hide(panel)
                }
            })
    }

    // MARK: Stacking

    /// Flattened-corner edges for the palette chrome on its stick lines.
    func stackEdges(_ panel: EditorPanel) -> (topFlat: Bool, bottomFlat: Bool) {
        let key = panel.rawValue
        return (stacks.isFollower(key), !stacks.followers(of: key).isEmpty)
    }

    /// Grabbing a follower's header detaches it: freeze it exactly where it
    /// rests (so the drag continues without a jump) and pull it out of its
    /// stack — the palettes below close up under whatever remains above.
    func detachForDrag(_ panel: EditorPanel, frozenAt position: CGSize, in dock: CGSize) {
        setPosition(panel, to: position, in: dock)
        stacks.detach(panel.rawValue)
    }

    /// Stick a released palette (with its own followers) under the palette
    /// identified by `targetKey`, locking the stack to the shared palette
    /// width: the resizable Layers palette adopts the fixed width whenever
    /// it is part of a stack.
    func attach(_ panel: EditorPanel, belowStackKey targetKey: String) {
        stacks.attach(panel.rawValue, below: targetKey)
        if stacks.isStacked(EditorPanel.layers.rawValue) {
            var layersSize = size(.layers)
            if layersSize.width != EditorPanel.panelWidth {
                layersSize.width = EditorPanel.panelWidth
                setSize(.layers, to: layersSize)
            }
        }
    }
}

/// The overlay hosting the palette rail and every open palette above the
/// editor canvas — ImageKid's `DockablePanelsLayer` arrangement: an
/// always-visible rail of small toggle buttons down the top-left, the
/// palettes floating to its right. Drag ends snap to a 20pt grid, clamp
/// inside the dock (at least 80pt of the palette and its whole header bar
/// stay reachable) and stick flush to the left/right dock edge within 14pt,
/// flattening the stuck corners like stack sticking does.
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

    /// Measured on-screen palette sizes (chrome included) — the stack layout
    /// and stick detection need real heights, not the rough estimates the
    /// default columns use. Sizes only change when content does, so this
    /// never churns mid-drag.
    @State private var measuredSizes: [EditorPanel: CGSize] = [:]
    /// Live translation of a dragged stack head, so its followers move along
    /// frame-by-frame. Deliberately a plain (non-observed) reference at this
    /// level: only the thin per-palette `StackDragOffset` wrappers subscribe,
    /// so per-frame drag updates re-run those offsets — never this body or
    /// the palette contents. Solo drags stay entirely inside
    /// FloatingToolPanel's @GestureState.
    @State private var stackDrag = StackDragState()

    private static let snapStep: CGFloat = 20
    /// Fallback before the first size measurement lands.
    private static let fallbackPanelSize = CGSize(width: EditorPanel.panelWidth, height: 200)

    var body: some View {
        // The rail sits left of the palette dock like ImageKid's; the
        // GeometryReader only feeds the dock size into positions — it
        // observes layout, never the session, so the no-session-rebuild
        // discipline above still holds.
        HStack(alignment: .top, spacing: 12) {
            panelRail
            GeometryReader { geo in
                let dock = geo.size
                palettes(in: dock)
                    .onChange(of: geo.size, initial: true) {
                        panels.migrateLegacyPositions(in: geo.size)
                    }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func palettes(in dock: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if panels.isExpanded(.fill) {
                palette(.fill, in: dock) { FillPanelContent(session: session) }
            }
            if panels.isExpanded(.stroke) {
                palette(.stroke, in: dock) { StrokePanelContent(session: session) }
            }
            if panels.isExpanded(.swatches) {
                palette(.swatches, in: dock) {
                    SwatchesPanelContent(session: session, workspace: workspace)
                }
            }
            if panels.isExpanded(.opacity) {
                palette(.opacity, in: dock) { OpacityPanelContent(session: session) }
            }
            if panels.isExpanded(.corners) {
                palette(.corners, in: dock) { CornersPanelContent(session: session) }
            }
            if panels.isExpanded(.transform) {
                palette(.transform, in: dock) { TransformPanelContent(session: session) }
            }
            if panels.isExpanded(.combine) {
                palette(.combine, in: dock) { CombinePanelContent(session: session) }
            }
            if panels.isExpanded(.align) {
                palette(.align, in: dock) { AlignPanelContent(session: session) }
            }
            if panels.isExpanded(.history) {
                palette(.history, in: dock) { HistoryPanelContent(session: session) }
            }
            Group {
                if panels.isExpanded(.styles) {
                    palette(.styles, in: dock) {
                        StylesPanelContent(session: session, workspace: workspace)
                    }
                }
                if panels.isExpanded(.layers) {
                    resizablePalette(.layers, in: dock) {
                        LayersPanelContent(session: session)
                    }
                }
            }
        }
        .onPreferenceChange(PaletteSizesKey.self) { measuredSizes = $0 }
        .onChange(of: panels.needsPlacement) { placePending(in: dock) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// ImageKid's `PanelDockRail` look for Fekthor: one small always-visible
    /// button per palette down the top-left, highlighted while its palette
    /// is open. A hidden palette opens into the next free dock slot, a
    /// minimized one (its button stays lit) restores where it was, an open
    /// one hides.
    private var panelRail: some View {
        VStack(spacing: 8) {
            ForEach(EditorPanel.allCases) { panel in
                let isActive = panels.visible.contains(panel)
                MinimizedPanelChip(systemImage: panel.systemImage, isActive: isActive) {
                    panels.railToggle(panel)
                }
                .help((isActive ? "Hide " : "Show ") + panel.title)
                .accessibilityLabel(panel.title)
                .accessibilityIdentifier("rail.\(panel.rawValue)")
            }
        }
    }

    private func palette(
        _ panel: EditorPanel, in dock: CGSize, @ViewBuilder content: () -> some View
    ) -> some View {
        StackDragOffset(
            drag: stackDrag, panelKey: panel.rawValue,
            headKey: panels.stacks.head(of: panel.rawValue)
        ) {
            FloatingToolPanel(
                title: panel.title,
                systemImage: panel.systemImage,
                width: EditorPanel.panelWidth,
                offset: displayBinding(panel, in: dock),
                onMinimize: { panels.minimize(panel) },
                snapStep: Self.snapStep,
                cornerRadius: 18,
                stackEdges: panels.stackEdges(panel),
                dockEdges: dockEdges(panel, in: dock),
                isStackFollower: panels.stacks.isFollower(panel.rawValue),
                onDragChanged: { paletteDragChanged(panel, translation: $0, in: dock) },
                onDragEnded: { _ in paletteDragEnded(panel, in: dock) }
            ) {
                PanelPerfProbe(label: panel.rawValue) { content() }
            }
        }
        .background(sizeReporter(panel))
        // Explicit stable identity: the free drag lives in @GestureState,
        // which survives only as long as the panel view's identity does.
        .id(panel)
    }

    /// A palette in FloatingToolPanel's resizable mode (Layers): the size
    /// persists next to the position, and the content fills the height.
    /// While stacked the resize handle disappears (the stack owns the width).
    private func resizablePalette(
        _ panel: EditorPanel, in dock: CGSize, @ViewBuilder content: () -> some View
    ) -> some View {
        StackDragOffset(
            drag: stackDrag, panelKey: panel.rawValue,
            headKey: panels.stacks.head(of: panel.rawValue)
        ) {
            FloatingToolPanel(
                title: panel.title,
                systemImage: panel.systemImage,
                width: EditorPanel.panelWidth,
                offset: displayBinding(panel, in: dock),
                onMinimize: { panels.minimize(panel) },
                snapStep: Self.snapStep,
                resizable: true,
                size: panels.sizeBinding(panel),
                minSize: CGSize(width: 220, height: 240),
                maxSize: CGSize(width: 520, height: 900),
                cornerRadius: 18,
                stackEdges: panels.stackEdges(panel),
                dockEdges: dockEdges(panel, in: dock),
                isStackFollower: panels.stacks.isFollower(panel.rawValue),
                onDragChanged: { paletteDragChanged(panel, translation: $0, in: dock) },
                onDragEnded: { _ in paletteDragEnded(panel, in: dock) }
            ) {
                PanelPerfProbe(label: panel.rawValue) { content() }
            }
        }
        .background(sizeReporter(panel))
        .id(panel)
    }

    /// Flat outer corners while the palette rests flush on a dock edge — the
    /// same fused look stack sticking gives, against the window edge.
    private func dockEdges(
        _ panel: EditorPanel, in dock: CGSize
    ) -> (leadingFlat: Bool, trailingFlat: Bool) {
        guard dock.width > 0 else { return (false, false) }
        let origin = displayPosition(panel, in: dock)
        let width = measuredSize(panel).width
        return (origin.width <= 0.5, origin.width + width >= dock.width - 0.5)
    }

    // MARK: Stacking

    private func sizeReporter(_ panel: EditorPanel) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(key: PaletteSizesKey.self, value: [panel: proxy.size])
        }
    }

    private func measuredSize(_ panel: EditorPanel) -> CGSize {
        measuredSizes[panel] ?? Self.fallbackPanelSize
    }

    /// Where the palette SETTLED right now: followers derive their spot from
    /// the stack head (flush, head-aligned), everything else uses its
    /// stored/docked position. Live drag translation is applied elsewhere —
    /// the head's inside FloatingToolPanel, its followers' by the thin
    /// StackDragOffset wrapper — so this never churns mid-drag.
    private func displayPosition(_ panel: EditorPanel, in dock: CGSize) -> CGSize {
        let key = panel.rawValue
        guard let stack = panels.stacks.stack(containing: key), stack.first != key,
            let headPanel = EditorPanel(rawValue: stack[0])
        else { return panels.position(panel, in: dock) }
        let head = panels.position(headPanel, in: dock)
        var sizes: [String: CGSize] = [:]
        for memberKey in stack {
            guard let member = EditorPanel(rawValue: memberKey) else { continue }
            sizes[memberKey] = measuredSize(member)
        }
        let origins = PanelStacks.layout(
            stack: stack, headOrigin: CGPoint(x: head.width, y: head.height), sizes: sizes)
        guard let origin = origins[key] else { return panels.position(panel, in: dock) }
        return CGSize(width: origin.x, height: origin.y)
    }

    /// The palette's settled frame — the input for stick detection, overlap
    /// checks and opening placement.
    private func paletteFrame(_ panel: EditorPanel, in dock: CGSize) -> CGRect {
        let origin = displayPosition(panel, in: dock)
        return CGRect(
            origin: CGPoint(x: origin.width, y: origin.height),
            size: measuredSize(panel))
    }

    private func displayBinding(_ panel: EditorPanel, in dock: CGSize) -> Binding<CGSize> {
        Binding(
            get: { self.displayPosition(panel, in: dock) },
            set: { self.settle(panel, at: $0, in: dock) })
    }

    /// Commit a released palette: clamp it inside the dock (at least 80pt of
    /// it, and always its full header bar) and stick it flush when it landed
    /// within 14pt of the left or right dock edge. Only drag ends write the
    /// binding, so the live drag stays raw — the grid snap and both magnets
    /// apply on release only.
    private func settle(_ panel: EditorPanel, at position: CGSize, in dock: CGSize) {
        let size = measuredSize(panel)
        let clamped = PanelPlacement.clamped(
            CGPoint(x: position.width, y: position.height), panelSize: size, dock: dock)
        let x = PanelPlacement.edgeStuckX(
            clamped.x, panelWidth: size.width, dockWidth: dock.width)
        panels.setPosition(panel, to: CGSize(width: x, height: clamped.y), in: dock)
    }

    private func paletteDragChanged(
        _ panel: EditorPanel, translation: CGSize, in dock: CGSize
    ) {
        let key = panel.rawValue
        if panels.stacks.isFollower(key) {
            // Taking a follower by the header detaches it — it moves alone.
            panels.detachForDrag(
                panel, frozenAt: displayPosition(panel, in: dock), in: dock)
        } else if !panels.stacks.followers(of: key).isEmpty {
            // Moving the top one moves the bottom one(s) along, live and
            // raw — the followers read this through their offset wrappers.
            if stackDrag.head != key { stackDrag.head = key }
            stackDrag.translation = translation
        }
    }

    private func paletteDragEnded(_ panel: EditorPanel, in dock: CGSize) {
        stackDrag.head = nil
        stackDrag.translation = .zero
        // Stick detection against the settled positions (the panel's own
        // offset — including its grid snap, clamp and edge stick — is
        // already committed).
        var frames: [String: CGRect] = [:]
        for candidate in EditorPanel.allCases where panels.isExpanded(candidate) {
            frames[candidate.rawValue] = paletteFrame(candidate, in: dock)
        }
        guard let dragged = frames[panel.rawValue] else { return }
        if let target = panels.stacks.snapCandidate(
            for: panel.rawValue, frame: dragged, others: frames)
        {
            panels.attach(panel, belowStackKey: target)
        }
    }

    // MARK: Opening placement

    /// A freshly opened palette must not restore a stale spot that overlaps
    /// an open palette or hangs outside the dock: keep the stored spot when
    /// it is clean, otherwise take the next free slot in the emptier dock
    /// column, computed against the open palettes' measured frames (the
    /// opening palette itself is still unmeasured — its estimate serves).
    private func placePending(in dock: CGSize) {
        guard dock.width > 0 else { return }
        for panel in panels.takePendingPlacement() {
            guard panels.isExpanded(panel) else { continue }
            let size = measuredSizes[panel]
                ?? CGSize(width: EditorPanel.panelWidth, height: panel.estimatedHeight)
            let others = EditorPanel.allCases
                .filter { $0 != panel && panels.isExpanded($0) }
                .map { paletteFrame($0, in: dock) }
            let stored = panels.position(panel, in: dock)
            let frame = CGRect(
                origin: CGPoint(x: stored.width, y: stored.height), size: size)
            let fits =
                frame.minX >= 0 && frame.maxX <= dock.width && frame.minY >= 0
                && frame.minY + PanelPlacement.headerHeight <= dock.height
            if fits && !PanelPlacement.overlaps(frame, any: others) { continue }
            let slot = PanelPlacement.openingSlot(
                panelSize: size, dock: dock, openFrames: others)
            panels.setPosition(panel, to: CGSize(width: slot.x, height: slot.y), in: dock)
        }
    }
}

/// Live stack-drag channel: which stack head is being dragged and its raw
/// translation this frame. The layer holds it as plain @State (a stable,
/// UNOBSERVED reference) and writes it from the head's drag callbacks; only
/// the StackDragOffset wrappers subscribe, so a drag frame re-evaluates thin
/// offsets — never the layer body or the palette contents.
@MainActor
private final class StackDragState: ObservableObject {
    @Published var head: String?
    @Published var translation: CGSize = .zero
}

/// Thin per-palette wrapper that shifts a stack FOLLOWER by its head's live
/// drag translation. The palette view is built once by the layer and passes
/// through untouched — this body is just an offset, which is what keeps
/// heavy palette contents from re-evaluating on every drag frame.
private struct StackDragOffset<Content: View>: View {
    @ObservedObject var drag: StackDragState
    let panelKey: String
    /// This palette's stack head key (nil when unstacked).
    let headKey: String?
    let content: Content

    init(
        drag: StackDragState, panelKey: String, headKey: String?,
        @ViewBuilder content: () -> Content
    ) {
        self.drag = drag
        self.panelKey = panelKey
        self.headKey = headKey
        self.content = content()
    }

    var body: some View {
        // The dragged head moves itself (FloatingToolPanel's @GestureState);
        // only its followers take the live translation here.
        let follows = drag.head != nil && drag.head == headKey && drag.head != panelKey
        content.offset(
            x: follows ? drag.translation.width : 0,
            y: follows ? drag.translation.height : 0)
    }
}

/// FEKTHOR_PANEL_PERF=1 logs one line per palette-content body evaluation.
/// A palette drag should log NOTHING — a line per frame means palette
/// contents are being rebuilt mid-drag again.
private struct PanelPerfProbe<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        let _ = PanelPerfLog.tick(label)
        content
    }
}

@MainActor
private enum PanelPerfLog {
    static let enabled =
        ProcessInfo.processInfo.environment["FEKTHOR_PANEL_PERF"] == "1"
    private static var counts: [String: Int] = [:]

    static func tick(_ label: String) {
        guard enabled else { return }
        counts[label, default: 0] += 1
        print("[fekthor.panel-perf] \(label) body evaluation #\(counts[label]!)")
    }
}

/// Collects every open palette's rendered size (the panel chrome included).
private struct PaletteSizesKey: PreferenceKey {
    static var defaultValue: [EditorPanel: CGSize] = [:]
    static func reduce(
        value: inout [EditorPanel: CGSize], nextValue: () -> [EditorPanel: CGSize]
    ) {
        value.merge(nextValue()) { _, next in next }
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
            if entries.isEmpty {
                // No 240pt scroll reservation while empty — the palette
                // stays compact instead of a tall hollow column.
                currentRow
                Text("No edits yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        currentRow
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                }
                .frame(maxHeight: 240)
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
    /// Radius for the any-shape fillet path (non-rect selections).
    @State private var anyShapeRadius: Double = 0

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
            } else if !session.selection.isEmpty {
                // Any other shape: one radius fillets every corner (or just
                // the selected points) through the live-corners engine.
                Text(
                    session.selection.count == 1
                        ? "Shape corners" : "\(session.selection.count) shapes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Slider(value: $anyShapeRadius, in: 0...48) { editing in
                        if !editing {
                            session.setCornerRadius(radius: anyShapeRadius)
                            session.endStyleEdit()
                        }
                    }
                    Text(String(format: "%.0f", anyShapeRadius))
                        .font(.caption.monospacedDigit())
                        .frame(width: 26, alignment: .trailing)
                }
                Text("Applies to all corners — select points to round only those, or drag the corner dots on the canvas.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a shape")
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
