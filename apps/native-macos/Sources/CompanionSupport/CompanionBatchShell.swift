import SwiftUI
import UniformTypeIdentifiers

struct CompanionBatchShell<Settings: View>: View {
    let title: String
    let subtitle: String
    let primaryActionTitle: String
    let isProcessing: Bool
    let items: [BatchItem]
    let progress: Double
    let acceptsDrop: ([URL]) -> Void
    let openFiles: () -> Void
    let clearCompleted: () -> Void
    let removeItem: (BatchItem.ID) -> Void
    let primaryAction: () -> Void
    let cancelAction: () -> Void
    @ViewBuilder var settings: Settings

    @State private var isDropTargeted = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                header
                settings
                Spacer(minLength: 0)
                controls
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
            .padding(24)
            .background(.regularMaterial)

            VStack(spacing: 16) {
                dropZone
                queueList
            }
            .padding(24)
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if isProcessing {
                ProgressView(value: progress)
                Button("Stop Batch", role: .cancel, action: cancelAction)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            } else {
                Button(primaryActionTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(items.isEmpty)
                    .frame(maxWidth: .infinity)
                Button("Clear Finished", action: clearCompleted)
                    .buttonStyle(.bordered)
                    .disabled(!items.contains(where: {
                        if case .done = $0.state { return true }
                        return false
                    }))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Drop images here")
                .font(.title2.weight(.semibold))
            Text("PNG, JPG, WebP, HEIC and more")
                .foregroundStyle(.secondary)
            Button {
                openFiles()
            } label: {
                Label("Choose Images", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [8, 7]))
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            loadDroppedURLs(from: providers)
            return true
        }
    }

    private var queueList: some View {
        List {
            ForEach(items) { item in
                BatchQueueRow(item: item) {
                    removeItem(item.id)
                }
            }
        }
        .listStyle(.inset)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("No images yet", systemImage: "tray", description: Text("Add a batch to get started."))
            }
        }
    }

    private func loadDroppedURLs(from providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url {
                    Task { @MainActor in
                        acceptsDrop([url])
                    }
                }
            }
        }
    }
}

private struct BatchQueueRow: View {
    let item: BatchItem
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                status
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Remove from queue")
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = item.thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.secondary.opacity(0.15))
                .frame(width: 58, height: 58)
                .overlay(Image(systemName: "photo"))
        }
    }

    @ViewBuilder private var status: some View {
        switch item.state {
        case .waiting:
            Text("Waiting")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .processing(let detail, let fraction):
            VStack(alignment: .leading, spacing: 4) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tint)
                if let fraction {
                    ProgressView(value: fraction)
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        case .done(let url):
            Text("Saved to \(url.lastPathComponent)")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
