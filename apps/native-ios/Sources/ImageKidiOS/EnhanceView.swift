import SwiftUI

/// Magic ▸ Enhance Image. Improves image quality (and optionally enlarges) on
/// device. We surface quality *grades* — Quick · High · Max — never the model
/// names; a grade that needs an AI model shows only its download size and grade.
struct EnhanceView: View {
    @ObservedObject var model: InferenceModel
    @Environment(\.dismiss) private var dismiss

    private static let qualityKey = "imagekid.enhance.quality"
    private static let sizeKey = "imagekid.enhance.size"

    @State private var quality: EnhanceQuality
    @State private var size: EnhanceSize

    let pixelSize: CGSize

    init(model: InferenceModel, pixelSize: CGSize) {
        self.model = model
        self.pixelSize = pixelSize
        let defaults = UserDefaults.standard
        _quality = State(initialValue: defaults.string(forKey: Self.qualityKey)
            .flatMap(EnhanceQuality.init(rawValue:)) ?? .high)
        _size = State(initialValue: defaults.string(forKey: Self.sizeKey)
            .flatMap(EnhanceSize.init(rawValue:)) ?? .same)
    }

    private var out: CGSize {
        CGSize(width: pixelSize.width * size.factor, height: pixelSize.height * size.factor)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quality") {
                    Picker("Quality", selection: $quality) {
                        ForEach(EnhanceQuality.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text(quality.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Size") {
                    Picker("Size", selection: $size) {
                        ForEach(EnhanceSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text("→ \(Int(out.width.rounded())) × \(Int(out.height.rounded())) px")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let download = quality.requiredModel, !model.downloader.isDownloaded(download) {
                    Section("Download") {
                        gradeDownloadRow(for: download)
                    }
                } else {
                    Section {
                        Button {
                            persist()
                            model.enhance(quality: quality, size: size)
                            dismiss()
                        } label: {
                            Label("Enhance", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Enhance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// A download row that names the *grade* and its size — never the model.
    @ViewBuilder
    private func gradeDownloadRow(for download: ModelDownloader.Model) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(quality.label) quality")
                Text("One-time download · \(download.approxSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch model.downloader.state(download) {
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.large)
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 84)
            case .failed:
                Button("Retry") { model.downloader.download(download) }
                    .buttonStyle(.bordered)
            case .notDownloaded:
                Button("Download") { model.downloader.download(download) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func persist() {
        UserDefaults.standard.set(quality.rawValue, forKey: Self.qualityKey)
        UserDefaults.standard.set(size.rawValue, forKey: Self.sizeKey)
    }
}
