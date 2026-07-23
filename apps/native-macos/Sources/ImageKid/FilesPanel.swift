import SwiftUI
import ImageKidKit
import UniformTypeIdentifiers

/// The open-files list, shared by the dockable Files panel and any legacy
/// sidebar presentation.
struct FilesListContent: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(appModel.items) { item in
                    fileRow(for: item)
                }
            }
            .padding(16)
            .thinScrollbars()
        }
        .frame(maxHeight: .infinity)
    }

    private func fileRow(for item: WorkspaceItem) -> some View {
        Button {
            if NSEvent.modifierFlags.contains(.command) {
                appModel.toggleItemSelection(item.id)
            } else {
                appModel.selectItem(item.id)
            }
        } label: {
            HStack(spacing: 9) {
                thumbnail(for: item)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(.white)
                    Text(item.isDirty ? "Unsaved changes" : "Saved")
                        .font(.caption2)
                        .foregroundStyle(item.isDirty ? .orange : .white.opacity(0.58))
                }

                Spacer(minLength: 0)

                Button {
                    appModel.closeItem(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.72))
                .help("Close without saving")
            }
            .padding(8)
            .background(rowBackground(for: item), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(rowBorder(for: item))
            }
        }
        .buttonStyle(.plain)
        // Drag an open file out to drop it into another canvas as a layer (future: image layers).
        .draggable(item.id.uuidString)
        .contextMenu {
            Button("Export…") {
                if !appModel.selectedItemIDs.contains(item.id) {
                    appModel.selectItem(item.id)
                }
                appModel.requestExport()
            }
            if appModel.selectedItemIDs.count > 1 {
                Menu("Actions on \(appModel.selectedItemIDs.count) files") {
                    Button("Remove Background") { appModel.batchRemoveBackground() }
                        .disabled(appModel.isRemovingBackground)
                    Button("Export…") { appModel.requestExport() }
                }
            }
            Button("Close Without Saving") {
                appModel.closeItem(item.id)
            }
        }
    }

    private func rowBackground(for item: WorkspaceItem) -> Color {
        if appModel.selectedItemID == item.id { return Color.accentColor.opacity(0.30) }
        if appModel.selectedItemIDs.contains(item.id) { return Color.accentColor.opacity(0.16) }
        return Color.white.opacity(0.07)
    }

    private func rowBorder(for item: WorkspaceItem) -> Color {
        if item.isDirty { return Color.orange.opacity(0.72) }
        if appModel.selectedItemIDs.contains(item.id) { return Color.accentColor.opacity(0.58) }
        return Color.white.opacity(0.09)
    }

    @ViewBuilder
    private func thumbnail(for item: WorkspaceItem) -> some View {
        if let image = item.thumbnail {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.10))
                Image(systemName: "film").foregroundStyle(.white.opacity(0.62))
            }
        }
    }
}

/// Dockable, movable, minimizable, resizable Files panel.
struct FilesPanel: View {
    @ObservedObject var appModel: AppModel
    @Binding var offset: CGSize
    @Binding var size: CGSize
    let onMinimize: () -> Void
    var stackEdges: (topFlat: Bool, bottomFlat: Bool) = (false, false)
    var dockEdges: (leadingFlat: Bool, trailingFlat: Bool) = (false, false)
    var isStackFollower: Bool = false
    var onDragChanged: ((CGSize) -> Void)? = nil
    var onDragEnded: ((CGSize) -> Void)? = nil

    var body: some View {
        FloatingToolPanel(
            title: "Files",
            systemImage: DockablePanel.files.spec.systemImage,
            offset: $offset,
            onMinimize: onMinimize,
            resizable: true,
            size: $size,
            stackEdges: stackEdges,
            dockEdges: dockEdges,
            isStackFollower: isStackFollower,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded,
            contentPadding: 0
        ) {
            if appModel.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Open images appear here.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(16)
            } else {
                FilesListContent(appModel: appModel)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            var handled = false
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL? = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    if let url { Task { @MainActor in appModel.load(url) } }
                }
            }
            return handled
        }
    }
}
