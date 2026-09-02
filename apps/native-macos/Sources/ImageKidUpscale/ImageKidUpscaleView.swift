import AppKit
import ImageKidInference
import SwiftUI

struct ImageKidUpscaleView: View {
    @ObservedObject var model: CompanionBatchModel
    @StateObject private var installer = ModelInstaller()
    @State private var scale = 2
    @State private var contentMode = UpscaleContentMode.automatic
    @State private var engine = CompanionBatchModel.UpscaleEngine.standard

    var body: some View {
        CompanionBatchShell(
            title: "Upscale",
            primaryActionTitle: "Generate Upscales",
            isProcessing: model.isProcessing,
            items: model.items,
            progress: model.overallProgress,
            existingResultCount: model.existingResultCount,
            acceptsDrop: model.addFiles,
            openFiles: model.openFiles,
            clearCompleted: model.clearCompleted,
            removeItems: model.removeItems,
            resetItems: model.resetItems,
            primaryAction: { policy in
                model.generate(existingResults: policy)
            },
            cancelAction: model.cancel
        ) {
            VStack(alignment: .leading, spacing: 20) {
                qualitySection
                scaleSection
                imageTypeSection
                destinationSection
                SourceActionSettings(model: model)
            }
        }
        .onAppear { model.operation = currentOperation }
        .onChange(of: engine) { _, _ in model.operation = currentOperation }
        .onChange(of: scale) { _, _ in model.operation = currentOperation }
        .onChange(of: contentMode) { _, _ in model.operation = currentOperation }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The destination folder can change behind the app's back.
            model.refreshExistingResults()
        }
    }

    private var currentOperation: CompanionBatchModel.Operation {
        .upscale(scale: scale, contentMode: contentMode, engine: engine)
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingLabel("Quality", systemImage: "sparkles")

            HStack(spacing: 8) {
                qualityButton(.standard, detail: "Fast and built in", systemImage: "bolt.fill")
                qualityButton(.bestQuality, detail: "AI detail recovery", systemImage: "wand.and.stars")
            }

            if engine == .bestQuality {
                ModelInstallRow(installer: installer, model: .realESRGAN)
            }
        }
    }

    private var scaleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingLabel("Make it bigger", systemImage: "arrow.up.left.and.arrow.down.right")

            HStack(spacing: 8) {
                ForEach([2, 4, 8], id: \.self) { option in
                    Button {
                        scale = option
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(option)×")
                                .font(.title3.weight(.bold))
                            Text(option == 2 ? "Twice" : option == 4 ? "Four times" : "Eight times")
                                .font(.caption2)
                                .foregroundStyle(scale == option ? .white.opacity(0.82) : .secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(scale == option ? Color.accentColor : Color.white.opacity(0.07))
                        .foregroundStyle(scale == option ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scale \(option) times")
                    .accessibilityAddTraits(scale == option ? .isSelected : [])
                }
            }
        }
    }

    private var imageTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingLabel("Tune for", systemImage: contentModeSymbol)
            Picker("Image Type", selection: $contentMode) {
                ForEach(UpscaleContentMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Text(contentModeDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingLabel("Save to", systemImage: "folder")
            Button {
                model.chooseDestinationFolder()
            } label: {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.tint)
                    Text(model.customDestinationURL?.lastPathComponent ?? "Next to each original")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            Toggle("Replace originals when possible", isOn: $model.overwriteOriginals)
                .controlSize(.small)
        }
    }

    private func qualityButton(
        _ option: CompanionBatchModel.UpscaleEngine,
        detail: String,
        systemImage: String
    ) -> some View {
        let isSelected = engine == option
        return Button {
            engine = option
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(option.label)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(10)
            .background(isSelected ? Color.accentColor : Color.white.opacity(0.07))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func settingLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private var contentModeSymbol: String {
        switch contentMode {
        case .automatic: "wand.and.rays"
        case .photoArtwork: "photo.on.rectangle.angled"
        case .textAndUI: "character.cursor.ibeam"
        }
    }

    private var contentModeDetail: String {
        switch contentMode {
        case .automatic: "ImageKid chooses the best treatment for every image."
        case .photoArtwork: "Keeps photos, textures, and illustration detail looking smooth."
        case .textAndUI: "Prioritises crisp type, icons, and interface captures."
        }
    }
}
