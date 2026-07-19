import SwiftUI

/// A row showing a downloadable model's state with a Download / Retry / Ready control.
struct ModelDownloadRow: View {
    @ObservedObject var model: InferenceModel
    let downloadable: ModelDownloader.Model

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(downloadable.title)
                Text(downloadable.approxSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch model.downloader.state(downloadable) {
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.large)
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 84)
            case .failed:
                Button("Retry") { model.downloader.download(downloadable) }
                    .buttonStyle(.bordered)
            case .notDownloaded:
                Button("Download") { model.downloader.download(downloadable) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Background-removal tool: pick an engine, refine, or download better models.
struct BackgroundToolSheet: View {
    @ObservedObject var model: InferenceModel
    @Environment(\.dismiss) private var dismiss
    var onRefine: () -> Void

    private var pendingModels: [ModelDownloader.Model] {
        [.birefnet, .u2net].filter { !model.downloader.isDownloaded($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Remove background") {
                    ForEach(model.availableBackgroundEngines) { engine in
                        Button {
                            model.removeBackground(engine: engine)
                            dismiss()
                        } label: {
                            Label(engine.title, systemImage: engine.systemImage)
                        }
                    }
                }
                Section {
                    Button {
                        dismiss()
                        onRefine()
                    } label: {
                        Label("Refine cutout", systemImage: "lasso")
                    }
                }
                if !pendingModels.isEmpty {
                    Section("Download better models") {
                        ForEach(pendingModels) { downloadable in
                            ModelDownloadRow(model: model, downloadable: downloadable)
                        }
                    }
                }
            }
            .navigationTitle("Background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

