import SwiftUI
import ImageKidKit

/// Actions for the current region selection, shown while the Select tool has an
/// active selection.
struct SelectionPanel: View {
    @ObservedObject var session: ImageSession
    @ObservedObject var appModel: AppModel
    @Binding var offset: CGSize
    let onClose: () -> Void

    var body: some View {
        FloatingToolPanel(
            title: "Selection",
            systemImage: "cursorarrow.and.square.on.square.dashed",
            width: 240,
            offset: $offset,
            onClose: onClose
        ) {
            VStack(spacing: 9) {
                action("Copy", "doc.on.doc") { appModel.copyImageSelectionToClipboard() }
                action("Crop to Selection", "crop") { appModel.cropSelection() }
                action("Magic Edit…", "wand.and.stars") { appModel.requestPromptEdit() }
                action("Export…", "square.and.arrow.up") { appModel.requestExport() }

                Rectangle().fill(.white.opacity(0.09)).frame(height: 1)

                Toggle("Snap to grid", isOn: $session.snapToGrid)
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Deselect") { session.selectionRect = nil }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .darkPanelControl()
        }
    }

    private func action(_ title: String, _ symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }
}
