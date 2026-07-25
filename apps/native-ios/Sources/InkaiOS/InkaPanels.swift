import BrushKit
import ImageKidKit
import InkaKit
import SwiftUI

/// Inka's dockable panels (iPad). The dock mechanics (model, rail, floating
/// chrome, placement, drag glue) all come from ImageKidKit — the same system
/// ImageKid and Fekthor use — so Inka's iPad panels dock, stack, stick and
/// minimise exactly like the rest of the family, and match the macOS app.
enum InkaPanel: String, CaseIterable, Identifiable, Hashable {
    case brushes
    case brush
    case colours
    case layers

    var id: String { rawValue }

    static let panelWidth: CGFloat = 320
    static let gridStep: CGFloat = 20

    var spec: DockPanelSpec<InkaPanel> {
        switch self {
        case .brushes:
            DockPanelSpec(
                id: self, title: "Brushes", systemImage: "paintbrush.pointed.fill",
                defaultPosition: CGSize(width: 0, height: 0),
                defaultSize: CGSize(width: Self.panelWidth, height: 160))
        case .brush:
            DockPanelSpec(
                id: self, title: "Brush", systemImage: "slider.horizontal.3",
                defaultPosition: CGSize(width: 0, height: 176),
                defaultSize: CGSize(width: Self.panelWidth, height: 480))
        case .colours:
            DockPanelSpec(
                id: self, title: "Colours", systemImage: "paintpalette.fill",
                defaultPosition: CGSize(width: 0, height: 668),
                defaultSize: CGSize(width: Self.panelWidth, height: 220))
        case .layers:
            DockPanelSpec(
                id: self, title: "Layers", systemImage: "square.3.layers.3d",
                defaultPosition: CGSize(width: 0, height: 900),
                defaultSize: CGSize(width: Self.panelWidth, height: 260))
        }
    }

    static var allSpecs: [DockPanelSpec<InkaPanel>] { allCases.map(\.spec) }
}

extension PanelDockModel where ID == InkaPanel {
    static func makeDefault() -> PanelDockModel<InkaPanel> {
        PanelDockModel(
            panels: InkaPanel.allSpecs,
            gridStep: InkaPanel.gridStep,
            minSize: CGSize(width: 280, height: 150),
            maxSize: CGSize(width: 380, height: 920),
            initiallyPresented: [.brushes, .brush, .layers],
            defaultsKey: "inka.ipad.paneldock")
    }
}

/// The Layers panel: the document's layers newest-on-top, with add/delete/
/// reorder, per-layer visibility and opacity, and active-layer selection.
struct InkaLayersPanel: View {
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
            title: "Layers", systemImage: "square.3.layers.3d",
            width: InkaPanel.panelWidth, offset: $offset, onMinimize: onMinimize,
            snapStep: InkaPanel.gridStep, resizable: true, size: size,
            minSize: CGSize(width: 280, height: 160), maxSize: CGSize(width: 380, height: 720),
            stackEdges: stackEdges, dockEdges: dockEdges, isStackFollower: isStackFollower,
            onDragChanged: onDragChanged, onDragEnded: onDragEnded
        ) {
            VStack(spacing: 8) {
                HStack {
                    Button { model.addLayer() } label: { Image(systemName: "plus") }
                    Button { model.moveLayer(model.activeLayerID, up: true) } label: {
                        Image(systemName: "arrow.up")
                    }
                    Button { model.moveLayer(model.activeLayerID, up: false) } label: {
                        Image(systemName: "arrow.down")
                    }
                    Spacer()
                    Button(role: .destructive) { model.deleteLayer(model.activeLayerID) } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(model.document.layers.count <= 1)
                }
                .buttonStyle(.bordered)

                // Newest on top, like every layers panel.
                ForEach(model.document.layers.reversed()) { layer in
                    row(layer)
                }
            }
        }
    }

    private func row(_ layer: Layer) -> some View {
        let active = layer.id == model.activeLayerID
        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    model.setLayerVisible(layer.id, !layer.isVisible)
                } label: {
                    Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                        .foregroundStyle(layer.isVisible ? .primary : .secondary)
                }
                .buttonStyle(.plain)

                Text(layer.name).font(.callout).lineLimit(1)
                Spacer()
                Text(kindLabel(layer)).font(.caption2).foregroundStyle(.tertiary)
            }
            if active {
                HStack(spacing: 6) {
                    Image(systemName: "circle.lefthalf.filled").font(.caption2)
                    Slider(
                        value: Binding(
                            get: { layer.opacity },
                            set: { model.setLayerOpacity(layer.id, $0) }), in: 0...1)
                    Text("\(Int(layer.opacity * 100))%")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(8)
        .background(
            active ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(active ? Color.accentColor : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { model.activeLayerID = layer.id }
    }

    private func kindLabel(_ layer: Layer) -> String {
        switch layer.content {
        case .strokes: "strokes"
        case .raster: "raster"
        case .imported: "image"
        }
    }
}

/// The Colours panel: the working colour well + eyedropper, a saved palette
/// (stored on the document) and the session's recent colours.
struct InkaColoursPanel: View {
    @ObservedObject var model: InkaModel
    @Binding var offset: CGSize
    let size: Binding<CGSize>
    let onMinimize: () -> Void
    let stackEdges: (topFlat: Bool, bottomFlat: Bool)
    let dockEdges: (leadingFlat: Bool, trailingFlat: Bool)
    let isStackFollower: Bool
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    private let columns = [GridItem(.adaptive(minimum: 30), spacing: 6)]

    var body: some View {
        FloatingToolPanel(
            title: "Colours", systemImage: "paintpalette.fill",
            width: InkaPanel.panelWidth, offset: $offset, onMinimize: onMinimize,
            snapStep: InkaPanel.gridStep, resizable: true, size: size,
            minSize: CGSize(width: 280, height: 150), maxSize: CGSize(width: 380, height: 540),
            stackEdges: stackEdges, dockEdges: dockEdges, isStackFollower: isStackFollower,
            onDragChanged: onDragChanged, onDragEnded: onDragEnded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ColorPicker("", selection: $model.color, supportsOpacity: false).labelsHidden()
                    Button {
                        model.tool = model.tool == .eyedropper ? .draw : .eyedropper
                    } label: {
                        Image(systemName: "eyedropper")
                    }
                    .buttonStyle(.bordered)
                    .tint(model.tool == .eyedropper ? .accentColor : nil)
                    Spacer()
                    Button { model.addCurrentSwatch() } label: { Image(systemName: "plus") }
                        .buttonStyle(.bordered)
                }

                if !model.document.palette.isEmpty {
                    label("Palette")
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(model.document.palette, id: \.self) { hex in
                            swatch(hex, removable: true)
                        }
                    }
                }

                if !model.recentColors.isEmpty {
                    label("Recent")
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(model.recentColors, id: \.self) { hex in
                            swatch(hex, removable: false)
                        }
                    }
                }
            }
        }
    }

    private func label(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func swatch(_ hex: String, removable: Bool) -> some View {
        let rgba = RGBA(hex: hex) ?? .black
        let selected = model.currentColorRGBA.hex == hex
        return Circle()
            .fill(rgba.color)
            .frame(width: 26, height: 26)
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Circle())
            .onTapGesture { model.selectSwatch(hex) }
            .contextMenu {
                if removable {
                    Button(role: .destructive) { model.removeSwatch(hex) } label: {
                        Label("Remove swatch", systemImage: "trash")
                    }
                }
            }
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
            minSize: CGSize(width: 280, height: 120), maxSize: CGSize(width: 380, height: 420),
            stackEdges: stackEdges, dockEdges: dockEdges, isStackFollower: isStackFollower,
            onDragChanged: onDragChanged, onDragEnded: onDragEnded
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 8) {
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
            minSize: CGSize(width: 300, height: 220), maxSize: CGSize(width: 380, height: 920),
            stackEdges: stackEdges, dockEdges: dockEdges, isStackFollower: isStackFollower,
            onDragChanged: onDragChanged, onDragEnded: onDragEnded
        ) {
            BrushEditorControls(model: model)
        }
    }
}
