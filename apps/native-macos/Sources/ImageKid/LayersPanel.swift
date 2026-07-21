import SwiftUI

/// Lists annotation layers front-to-back, with selection, reordering,
/// duplication and deletion. Front-most layer sits at the top of the list.
struct LayersPanel: View {
    @ObservedObject var session: ImageSession
    @ObservedObject var appModel: AppModel
    @Binding var offset: CGSize
    @Binding var size: CGSize
    let onMinimize: () -> Void

    /// Front-most first (last in the draw array renders on top).
    private var orderedLayers: [Annotation] { session.annotations.reversed() }

    var body: some View {
        FloatingToolPanel(
            title: "Layers",
            systemImage: "square.3.layers.3d",
            offset: $offset,
            onMinimize: onMinimize,
            snapStep: AppModel.panelGridStep,
            resizable: true,
            size: $size
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if session.annotations.isEmpty && session.imageLayers.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Drag an image in, or add annotations — they appear here as layers.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(session.imageLayers.reversed()) { layer in
                                imageLayerRow(layer)
                            }
                            ForEach(orderedLayers) { layer in
                                row(layer)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)

                    controlBar
                }
            }
        }
    }

    private func row(_ layer: Annotation) -> some View {
        let isSelected = session.selectedAnnotationID == layer.id
        return Button {
            session.selectedAnnotationID = layer.id
            session.selectedLayerID = nil
            session.selectionRect = nil
            if appModel.activeTool == .view { appModel.activeTool = .select }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(for: layer))
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22)
                Text(label(for: layer))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.30) : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func imageLayerRow(_ layer: ImageLayer) -> some View {
        let isSelected = session.selectedLayerID == layer.id
        return HStack(spacing: 10) {
            Image(nsImage: layer.image)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .opacity(layer.isVisible ? 1 : 0.35)
            Text(layer.name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            Button {
                session.toggleImageLayerVisibility(id: layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? Color.accentColor.opacity(0.30) : Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            session.selectedLayerID = layer.id
            session.selectedAnnotationID = nil
        }
    }

    private var controlBar: some View {
        HStack(spacing: 6) {
            control("arrow.up", help: "Bring forward") {
                if let id = session.selectedLayerID { session.moveImageLayer(id: id, forward: true) }
                else if let id = session.selectedAnnotationID { session.moveAnnotation(id: id, forward: true) }
            }
            control("arrow.down", help: "Send backward") {
                if let id = session.selectedLayerID { session.moveImageLayer(id: id, forward: false) }
                else if let id = session.selectedAnnotationID { session.moveAnnotation(id: id, forward: false) }
            }
            Spacer()
            control("plus.square.on.square", help: "Duplicate") {
                if let id = session.selectedAnnotationID { session.duplicateAnnotation(id: id) }
            }
            .disabled(session.selectedAnnotationID == nil)
            control("trash", help: "Delete") {
                if let id = session.selectedLayerID { session.removeImageLayer(id: id) }
                else if let id = session.selectedAnnotationID { session.removeAnnotation(id: id) }
            }
        }
        .disabled(session.selectedAnnotationID == nil && session.selectedLayerID == nil)
        .padding(.top, 2)
    }

    private func control(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 28)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func icon(for layer: Annotation) -> String {
        if layer.isText { return "textformat" }
        return layer.drawingMode?.symbolName ?? "square"
    }

    private func label(for layer: Annotation) -> String {
        if layer.isText {
            let text = layer.textValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "Text" : text
        }
        return layer.drawingMode?.label ?? "Shape"
    }
}
