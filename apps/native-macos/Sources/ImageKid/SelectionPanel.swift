import SwiftUI
import ImageKidKit

/// Actions for the current region selection, shown while the Select tool has an
/// active selection.
struct SelectionPanel: View {
    @EnvironmentObject private var library: ColorLibrary
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
                fillAction
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

    private var fillAction: some View {
        HStack(spacing: 8) {
            Button {
                appModel.fillSelection(with: library.foreground)
            } label: {
                Label("Fill", systemImage: "paintbrush.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Menu {
                Button("Foreground") { appModel.fillSelection(with: library.foreground) }
                Button("Background") { appModel.fillSelection(with: library.background) }
                Divider()
                ForEach(library.baseColors) { swatch in
                    Button(swatch.hex) { appModel.fillSelection(with: swatch.nsColor) }
                }
            } label: {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: library.foreground))
                    .frame(width: 26, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.3)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose a fill colour")
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
