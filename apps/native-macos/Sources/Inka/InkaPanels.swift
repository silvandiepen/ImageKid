import BrushKit
import ImageKidKit
import SwiftUI

/// Inka's dockable panels. The dock mechanics (model, rail, floating chrome,
/// placement, drag glue) all come from ImageKidKit — the same system ImageKid
/// and Fekthor use — so Inka's panels dock, stack, stick and minimise exactly
/// like the rest of the family.
enum InkaPanel: String, CaseIterable, Identifiable, Hashable {
    case brushes
    case brush

    var id: String { rawValue }

    static let panelWidth: CGFloat = 300
    static let gridStep: CGFloat = 20

    var spec: DockPanelSpec<InkaPanel> {
        switch self {
        case .brushes:
            DockPanelSpec(
                id: self, title: "Brushes", systemImage: "paintbrush.pointed.fill",
                defaultPosition: CGSize(width: 0, height: 0),
                defaultSize: CGSize(width: Self.panelWidth, height: 150))
        case .brush:
            DockPanelSpec(
                id: self, title: "Brush", systemImage: "slider.horizontal.3",
                defaultPosition: CGSize(width: 0, height: 166),
                defaultSize: CGSize(width: Self.panelWidth, height: 560))
        }
    }

    static var allSpecs: [DockPanelSpec<InkaPanel>] { allCases.map(\.spec) }
}

extension PanelDockModel where ID == InkaPanel {
    static func makeDefault() -> PanelDockModel<InkaPanel> {
        PanelDockModel(
            panels: InkaPanel.allSpecs,
            gridStep: InkaPanel.gridStep,
            minSize: CGSize(width: 260, height: 140),
            maxSize: CGSize(width: 360, height: 900),
            initiallyPresented: [.brushes, .brush],
            defaultsKey: "inka.paneldock")
    }
}

/// The Brushes panel: the built-in / imported presets as a grid; tap to make one
/// the working brush.
struct InkaBrushesPanel: View {
    @ObservedObject var model: InkaModel
    @Binding var offset: CGSize
    let size: Binding<CGSize>
    let onMinimize: () -> Void
    let stackEdges: (topFlat: Bool, bottomFlat: Bool)
    let dockEdges: (leadingFlat: Bool, trailingFlat: Bool)
    let isStackFollower: Bool
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    var body: some View {
        FloatingToolPanel(
            title: "Brushes", systemImage: "paintbrush.pointed.fill",
            width: InkaPanel.panelWidth, offset: $offset, onMinimize: onMinimize,
            snapStep: InkaPanel.gridStep, resizable: true, size: size,
            minSize: CGSize(width: 260, height: 120), maxSize: CGSize(width: 360, height: 400),
            stackEdges: stackEdges, dockEdges: dockEdges, isStackFollower: isStackFollower,
            onDragChanged: onDragChanged, onDragEnded: onDragEnded
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                ForEach(model.document.brushes) { brush in
                    Button {
                        model.selectBrush(brush.id)
                    } label: {
                        VStack(spacing: 4) {
                            BrushPreview(brush: swatchBrush(brush))
                                .frame(height: 34)
                                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(
                                            model.currentBrushID == brush.id
                                                ? Color.accentColor : .clear, lineWidth: 2))
                            Text(brush.name).font(.caption2).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A fixed-size copy so every swatch preview reads at the same scale.
    private func swatchBrush(_ brush: Brush) -> Brush {
        var b = brush
        b.size = min(brush.size, 14)
        return b
    }
}

/// The Brush panel: the full editor controls inside the shared floating chrome.
struct InkaBrushPanel: View {
    @ObservedObject var model: InkaModel
    @Binding var offset: CGSize
    let size: Binding<CGSize>
    let onMinimize: () -> Void
    let stackEdges: (topFlat: Bool, bottomFlat: Bool)
    let dockEdges: (leadingFlat: Bool, trailingFlat: Bool)
    let isStackFollower: Bool
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    var body: some View {
        FloatingToolPanel(
            title: "Brush", systemImage: "slider.horizontal.3",
            width: InkaPanel.panelWidth, offset: $offset, onMinimize: onMinimize,
            snapStep: InkaPanel.gridStep, resizable: true, size: size,
            minSize: CGSize(width: 280, height: 220), maxSize: CGSize(width: 360, height: 900),
            stackEdges: stackEdges, dockEdges: dockEdges, isStackFollower: isStackFollower,
            onDragChanged: onDragChanged, onDragEnded: onDragEnded
        ) {
            BrushEditorControls(model: model)
        }
    }
}
