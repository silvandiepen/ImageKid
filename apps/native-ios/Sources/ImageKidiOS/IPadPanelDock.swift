import SwiftUI
import ImageKidKit

/// The iPad's dockable floating panels. The reusable dock mechanics (grid
/// snapping, magnetic stacking, minimize, persistence) live in ImageKidKit;
/// this mirrors the macOS DockablePanel setup on touch.
enum IPadDockPanel: String, CaseIterable, Identifiable, Hashable {
    case annotate
    case colours
    case mask
    case layers
    case history

    var id: String { rawValue }

    static let gridStep: CGFloat = 20

    var spec: DockPanelSpec<IPadDockPanel> {
        switch self {
        case .annotate:
            DockPanelSpec(id: self, title: "Draw", systemImage: "pencil.tip.crop.circle",
                          defaultPosition: .zero, defaultSize: CGSize(width: 340, height: 470))
        case .colours:
            DockPanelSpec(id: self, title: "Colours", systemImage: "eyedropper",
                          defaultPosition: CGSize(width: 0, height: 320), defaultSize: CGSize(width: 340, height: 260))
        case .mask:
            DockPanelSpec(id: self, title: "Mask", systemImage: "person.and.background.dotted",
                          defaultPosition: .zero, defaultSize: CGSize(width: 340, height: 360))
        case .layers:
            DockPanelSpec(id: self, title: "Layers", systemImage: "square.3.layers.3d",
                          defaultPosition: .zero, defaultSize: CGSize(width: 300, height: 380))
        case .history:
            DockPanelSpec(id: self, title: "History", systemImage: "clock.arrow.circlepath",
                          defaultPosition: .zero, defaultSize: CGSize(width: 300, height: 420))
        }
    }

    static var allSpecs: [DockPanelSpec<IPadDockPanel>] { allCases.map(\.spec) }
}

extension PanelDockModel where ID == IPadDockPanel {
    /// One shared dock for every iPad panel, persisted under a single key.
    static func makeIPadDock() -> PanelDockModel<IPadDockPanel> {
        PanelDockModel(
            panels: IPadDockPanel.allSpecs,
            gridStep: IPadDockPanel.gridStep,
            minSize: CGSize(width: 260, height: 200),
            maxSize: CGSize(width: 520, height: 800),
            initiallyPresented: [],
            defaultsKey: "ipad.panels"
        )
    }
}

/// The movable dockable panels plus their chip rail, drawn over the iPad
/// canvas. Same mechanics as the macOS DockablePanelsLayer: panels stick
/// magnetically when one is dropped onto another's bottom edge, the stack
/// moves with its head, and dragging a lower panel's header detaches it.
struct IPadPanelsLayer: View {
    @ObservedObject var model: InferenceModel
    @ObservedObject var dock: PanelDockModel<IPadDockPanel>

    /// The annotate panel doubles as the Text options while the text tool is up.
    let isTextTool: Bool
    @Binding var annotationKind: Annotation.Kind
    @Binding var annotationColor: Color
    @Binding var annotationWidthFraction: CGFloat
    @Binding var annotationBrush: BrushPreset
    @Binding var annotationOpacity: CGFloat
    @Binding var annotationSoftness: CGFloat
    @Binding var textSizeFraction: CGFloat
    @Binding var annotations: [Annotation]
    @Binding var layers: [EditorLayer]
    @Binding var selectedAnnotationID: UUID?
    @Binding var selectedLayerID: UUID?
    let currentSample: SampledColor?
    let onSaveSample: () -> Void
    let onAnnotateCancel: () -> Void
    let onAnnotateApply: () -> Void
    /// Mask panel state and actions (the session itself lives in ContentView).
    let maskHasMask: Bool
    let maskEngineTitle: String
    let isBusy: Bool
    @Binding var maskRevealMode: Bool
    @Binding var maskWidthFraction: CGFloat
    @Binding var maskSoftness: CGFloat
    let onMaskFromSubject: () -> Void
    let onMaskCancel: () -> Void
    let onMaskApply: () -> Void
    /// Rail taps on the tool-driven panels (annotate, colours) toggle their
    /// tool in ContentView; the dock's presented set follows the tool.
    let onToggleTool: (IPadDockPanel) -> Void

    /// Live translation of a dragged stack head, so its followers move
    /// along frame-by-frame. Solo drags never touch this state.
    @State private var stackDragHead: IPadDockPanel?
    @State private var stackDragTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if dock.isExpanded(.annotate) {
                    panel(
                        .annotate,
                        title: isTextTool ? "Text" : "Draw",
                        systemImage: annotateIcon
                    ) {
                        AnnotationControls(
                            selectedTool: $annotationKind,
                            color: $annotationColor,
                            widthFraction: $annotationWidthFraction,
                            brush: $annotationBrush,
                            opacity: $annotationOpacity,
                            softness: $annotationSoftness,
                            textSizeFraction: $textSizeFraction,
                            annotations: $annotations,
                            selectedAnnotationID: $selectedAnnotationID,
                            defaultKind: isTextTool ? .text : .freehand,
                            onCancel: onAnnotateCancel,
                            onApply: onAnnotateApply
                        )
                    }
                }
                if dock.isExpanded(.colours) {
                    panel(.colours) {
                        ColourSampleControls(model: model, current: currentSample, onSave: onSaveSample)
                    }
                }
                if dock.isExpanded(.mask) {
                    panel(.mask) {
                        MaskControls(
                            hasMask: maskHasMask,
                            isBusy: isBusy,
                            engineTitle: maskEngineTitle,
                            revealMode: $maskRevealMode,
                            widthFraction: $maskWidthFraction,
                            softness: $maskSoftness,
                            onMaskFromSubject: onMaskFromSubject,
                            onCancel: onMaskCancel,
                            onApply: onMaskApply
                        )
                    }
                }
                if dock.isExpanded(.layers) {
                    panel(.layers) {
                        LayersPanelContent(
                            annotations: $annotations,
                            layers: $layers,
                            selectedAnnotationID: $selectedAnnotationID,
                            selectedLayerID: $selectedLayerID
                        )
                    }
                }
                if dock.isExpanded(.history) {
                    panel(.history) {
                        HistoryPanelContent(model: model)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .overlay(alignment: .topTrailing) { rail }
            .onAppear { seedDefaultPositions(in: geo.size) }
            .onChange(of: dock.presented) { _, _ in seedDefaultPositions(in: geo.size) }
        }
    }

    private var annotateIcon: String {
        isTextTool ? "textformat" : "pencil.tip.crop.circle"
    }

    /// Always-visible vertical strip of 44pt chips under the top bar, one per
    /// panel — the touch equivalent of the macOS PanelDockRail. Minimized
    /// panels restore from here; hidden ones show; open ones hide.
    private var rail: some View {
        VStack(spacing: 10) {
            ForEach(IPadDockPanel.allCases) { id in
                MinimizedPanelChip(
                    systemImage: id == .annotate ? annotateIcon : id.spec.systemImage,
                    isActive: dock.presented.contains(id)
                ) {
                    railTap(id)
                }
                .accessibilityLabel(
                    (dock.presented.contains(id) ? "Hide " : "Show ") + id.spec.title)
            }
        }
    }

    private func railTap(_ id: IPadDockPanel) {
        switch id {
        case .annotate, .colours, .mask:
            // Tool-driven panels: a minimized panel restores in place; any
            // other state toggles the underlying tool, which shows/hides the
            // panel through the dock sync in ContentView.
            if dock.presented.contains(id), dock.minimized.contains(id) {
                dock.restore(id)
            } else {
                onToggleTool(id)
            }
        case .layers, .history:
            dock.railToggle(id)
        }
    }

    /// A dock-managed FloatingToolPanel with the shared dark-glass chrome,
    /// wired for magnetic stacking and the minimize chip rail.
    private func panel<Content: View>(
        _ id: IPadDockPanel,
        title: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        FloatingToolPanel(
            title: title ?? id.spec.title,
            systemImage: systemImage ?? id.spec.systemImage,
            offset: offsetBinding(id),
            onMinimize: { dock.minimize(id) },
            resizable: true,
            size: dock.sizeBinding(id),
            minSize: dock.minSize,
            maxSize: dock.maxSize,
            stackEdges: dock.stackEdges(of: id),
            isStackFollower: dock.isStackFollower(id),
            onDragChanged: { dragChanged(id, translation: $0) },
            onDragEnded: { _ in dragEnded(id) }
        ) {
            content()
                .darkPanelControl()
                // Native controls (segmented picker, bordered buttons) should
                // render their dark variants on the dark-glass chrome.
                .environment(\.colorScheme, .dark)
        }
    }

    /// Followers rest flush under their stack head (plus the head's live
    /// drag translation); heads and unstacked panels use their stored spot.
    private func offsetBinding(_ id: IPadDockPanel) -> Binding<CGSize> {
        Binding(
            get: {
                var origin = dock.displayPosition(id)
                if let head = stackDragHead, id != head,
                    dock.stacks.head(of: dock.stackKey(id)) == dock.stackKey(head)
                {
                    origin.width += stackDragTranslation.width
                    origin.height += stackDragTranslation.height
                }
                return origin
            },
            set: { dock.setPosition(id, to: $0) })
    }

    private func dragChanged(_ id: IPadDockPanel, translation: CGSize) {
        if dock.isStackFollower(id) {
            // Taking a follower by the header detaches it — it moves alone
            // and the panels below close up.
            dock.detachForDrag(id)
        } else if !dock.stacks.followers(of: dock.stackKey(id)).isEmpty {
            // Moving the top one moves the bottom one(s) along, live.
            stackDragHead = id
            stackDragTranslation = translation
        }
    }

    private func dragEnded(_ id: IPadDockPanel) {
        stackDragHead = nil
        stackDragTranslation = .zero
        // Stick detection against the settled, grid-snapped positions.
        dock.snapReleased(id)
    }

    /// The trailing-edge panels can't have a static default position (the
    /// spec has no canvas width), so the first time they are shown without a
    /// stored spot, park them by the rail — matching where the old
    /// top-trailing Layers panel used to rest.
    private func seedDefaultPositions(in size: CGSize) {
        guard size.width > 0 else { return }
        let railClearance: CGFloat = 64
        for id in [IPadDockPanel.layers, .history] where dock.positions[id] == nil {
            let x = max(0, size.width - id.spec.defaultSize.width - railClearance)
            let y: CGFloat = id == .history ? 440 : 0
            dock.setPosition(id, to: CGSize(width: x, height: min(y, max(0, size.height - 200))))
        }
    }
}

/// A named, jump-to-any-step history timeline, newest step on top (ports the
/// macOS HistoryPanel to the iOS model). The current step is highlighted;
/// steps above it are redoable and dimmed. Tapping a step restores it without
/// dropping the timeline — see InferenceModel.jump(to:). Shared by the iPad
/// floating panel and the compact-width sheet.
struct HistoryPanelContent: View {
    @ObservedObject var model: InferenceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("\(model.historyIndex + 1) of \(model.history.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                historyButton("arrow.uturn.backward", label: "Undo") { model.undo() }
                    .disabled(!model.canUndo)
                historyButton("arrow.uturn.forward", label: "Redo") { model.redo() }
                    .disabled(!model.canRedo)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        // Newest first: walk the timeline back to front, so
                        // the current row sits on top unless redo steps exist
                        // above it (those stay visible, dimmed).
                        ForEach(Array(model.history.enumerated()).reversed(), id: \.element.id) { index, step in
                            row(index: index, step: step)
                                .id(index)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: model.historyIndex) { _, newValue in
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
    }

    private func historyButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func row(index: Int, step: HistoryStep) -> some View {
        let isCurrent = index == model.historyIndex
        let isFuture = index > model.historyIndex
        return Button {
            model.jump(to: index)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: step.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22)
                Text(step.name)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                if isCurrent {
                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(index)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                isCurrent ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .opacity(isFuture ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
