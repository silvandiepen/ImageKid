import SwiftUI

/// Lists annotation layers front-to-back, with selection, reordering,
/// duplication and deletion. Front-most layer sits at the top of the list.
struct LayersPanel: View {
    @ObservedObject var session: ImageSession
    @ObservedObject var appModel: AppModel
    @Binding var offset: CGSize
    let onClose: () -> Void

    /// Front-most first (last in the draw array renders on top).
    private var orderedLayers: [Annotation] { session.annotations.reversed() }

    var body: some View {
        FloatingToolPanel(
            title: "Layers",
            systemImage: "square.3.layers.3d",
            width: 280,
            offset: $offset,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if session.annotations.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Annotations you add appear here as layers.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(orderedLayers) { layer in
                                row(layer)
                            }
                        }
                    }
                    .frame(maxHeight: 340)

                    controlBar
                }
            }
        }
    }

    private func row(_ layer: Annotation) -> some View {
        let isSelected = session.selectedAnnotationID == layer.id
        return Button {
            session.selectedAnnotationID = layer.id
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

    private var controlBar: some View {
        HStack(spacing: 6) {
            control("arrow.up", help: "Bring forward") {
                if let id = session.selectedAnnotationID { session.moveAnnotation(id: id, forward: true) }
            }
            control("arrow.down", help: "Send backward") {
                if let id = session.selectedAnnotationID { session.moveAnnotation(id: id, forward: false) }
            }
            Spacer()
            control("plus.square.on.square", help: "Duplicate") {
                if let id = session.selectedAnnotationID { session.duplicateAnnotation(id: id) }
            }
            control("trash", help: "Delete") {
                if let id = session.selectedAnnotationID { session.removeAnnotation(id: id) }
            }
        }
        .disabled(session.selectedAnnotationID == nil)
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
