import SwiftUI

/// Magic ▸ Enhance Image. Improves image quality (and optionally enlarges) on
/// device. We surface quality *grades* — Quick · High · Max — never the model
/// names; a grade that needs an AI model shows only its download size and grade.
struct EnhanceSheet: View {
    let pixelSize: CGSize
    let isApplying: Bool
    let onCancel: () -> Void
    let onApply: (EnhanceQuality, EnhanceSize) -> Void

    /// Shared with Settings so a download started in either place shows its
    /// progress in both.
    @ObservedObject private var modelDownloader = ModelDownloader.shared
    @AppStorage("enhanceQuality") private var qualityRaw = EnhanceQuality.high.rawValue
    @AppStorage("enhanceSize") private var sizeRaw = EnhanceSize.same.rawValue

    private var quality: EnhanceQuality {
        get { EnhanceQuality(rawValue: qualityRaw) ?? .high }
        nonmutating set { qualityRaw = newValue.rawValue }
    }
    private var size: EnhanceSize {
        get { EnhanceSize(rawValue: sizeRaw) ?? .same }
        nonmutating set { sizeRaw = newValue.rawValue }
    }

    private var outputSize: CGSize {
        CGSize(width: pixelSize.width * size.factor, height: pixelSize.height * size.factor)
    }

    /// Ready when built-in, or the grade's model is downloaded.
    private var isReady: Bool {
        guard let model = quality.requiredModel else { return true }
        return model.isDownloaded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Enhance Image", systemImage: "wand.and.stars")
                    .font(.title3.weight(.semibold))
                Text("Improve detail on-device. Pick a quality grade and an output size.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Quality")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Quality", selection: qualityBinding) {
                    ForEach(EnhanceQuality.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(quality.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Size")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Size", selection: sizeBinding) {
                    ForEach(EnhanceSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("→ \(Int(outputSize.width.rounded())) × \(Int(outputSize.height.rounded())) px")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let model = quality.requiredModel, !model.isDownloaded {
                downloadRow(for: model)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .disabled(isApplying)
                    .keyboardShortcut(.cancelAction)
                Button(isApplying ? "Enhancing…" : "Enhance") {
                    onApply(quality, size)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying || !isReady)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    /// A download row that names the *grade* and its size — never the model.
    @ViewBuilder
    private func downloadRow(for model: CoreMLModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(quality.label) quality")
                    .font(.callout.weight(.semibold))
                Text("One-time download · \(model.approxSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch modelDownloader.state(model) {
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 120)
            case .failed(let message):
                Button("Retry") { modelDownloader.download(model) }
                    .help(message)
            case .notDownloaded:
                Button("Download") { modelDownloader.download(model) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var qualityBinding: Binding<EnhanceQuality> {
        Binding(get: { quality }, set: { quality = $0 })
    }
    private var sizeBinding: Binding<EnhanceSize> {
        Binding(get: { size }, set: { size = $0 })
    }
}
