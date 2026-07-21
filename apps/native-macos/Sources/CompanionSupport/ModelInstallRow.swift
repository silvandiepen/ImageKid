import SwiftUI

struct ModelInstallRow: View {
    @ObservedObject var downloader: ModelDownloader
    let model: CoreMLModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.headline)
                    Text(model.approxSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                action
            }

            if case .downloading(let progress) = downloader.state(model) {
                ProgressView(value: progress)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var action: some View {
        switch downloader.state(model) {
        case .ready:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Button("Try Again") {
                downloader.download(model)
            }
            .buttonStyle(.bordered)
        case .notDownloaded:
            Button("Install") {
                downloader.download(model)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
