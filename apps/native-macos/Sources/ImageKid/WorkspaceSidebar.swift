import SwiftUI

struct WorkspaceSidebar: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var isCollapsed: Bool

    var body: some View {
        Group {
            if isCollapsed {
                collapsedPanel
            } else {
                expandedPanel
            }
        }
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.80), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.36), radius: 28, y: 12)
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Files", systemImage: "sidebar.left")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)

                Spacer()

                Button {
                    isCollapsed = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .help("Collapse sidebar")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(appModel.items) { item in
                        fileRow(for: item)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 236, height: 360)
    }

    private var collapsedPanel: some View {
        VStack(spacing: 10) {
            Button {
                isCollapsed = false
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)
            .help("Show sidebar")

            if let selectedItem = appModel.selectedItem {
                thumbnail(for: selectedItem)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(selectedItem.isDirty ? Color.orange.opacity(0.78) : Color.white.opacity(0.16))
                    }
            }

            Text("\(appModel.items.count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 28, height: 20)
                .background(.white.opacity(0.10), in: Capsule())
        }
        .padding(8)
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
            .background(
                rowBackground(for: item),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(rowBorder(for: item))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Export…") {
                if !appModel.selectedItemIDs.contains(item.id) {
                    appModel.selectItem(item.id)
                }
                appModel.requestExport()
            }
            Button("Close Without Saving") {
                appModel.closeItem(item.id)
            }
        }
    }

    private func rowBackground(for item: WorkspaceItem) -> Color {
        if appModel.selectedItemID == item.id {
            return Color.accentColor.opacity(0.30)
        }
        if appModel.selectedItemIDs.contains(item.id) {
            return Color.accentColor.opacity(0.16)
        }
        return Color.white.opacity(0.07)
    }

    private func rowBorder(for item: WorkspaceItem) -> Color {
        if item.isDirty {
            return Color.orange.opacity(0.72)
        }
        if appModel.selectedItemIDs.contains(item.id) {
            return Color.accentColor.opacity(0.58)
        }
        return Color.white.opacity(0.09)
    }

    @ViewBuilder
    private func thumbnail(for item: WorkspaceItem) -> some View {
        if let image = item.thumbnail {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                Image(systemName: "film")
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }
}
