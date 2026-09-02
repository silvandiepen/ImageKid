import AppKit
import SwiftUI

struct ImageKidCutoutView: View {
    @ObservedObject var model: CompanionBatchModel
    @StateObject private var installer = ModelInstaller()
    /// Remembered across launches: picking Best Quality is a deliberate choice and
    /// re-picking it every session is busywork.
    @AppStorage("cutout.engine") private var engine = CompanionBatchModel.CutoutEngine.builtIn
    @State private var editingItem: BatchItem?

    @ViewBuilder private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    /// Compact folder chooser used for the optional watched-folder setting.
    private func folderRow(
        _ title: String,
        name: String?,
        icon: String,
        help: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Button(action: action) {
                Label(name ?? "Choose...", systemImage: icon)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .help(help ?? "")
        }
    }

    var body: some View {
        CompanionBatchShell(
            title: "Cutout",
            primaryActionTitle: "Generate Cutouts",
            isProcessing: model.isProcessing,
            items: model.items,
            progress: model.overallProgress,
            existingResultCount: model.existingResultCount,
            acceptsDrop: model.addFiles,
            openFiles: model.openFiles,
            clearCompleted: model.clearCompleted,
            removeItems: model.removeItems,
            resetItems: model.resetItems,
            openEditor: { editingItem = $0 },
            primaryAction: { policy in
                model.generate(existingResults: policy)
            },
            cancelAction: model.cancel
        ) {
            VStack(alignment: .leading, spacing: 22) {
                // Two questions, in the order they are asked: how to cut, and where the
                // files go. Everything that was only explaining itself has moved into a
                // tooltip or gone.
                section("Quality") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 8
                    ) {
                        qualityButton(
                            .builtIn,
                            detail: "Fast and built in",
                            systemImage: "person.crop.circle"
                        )
                        qualityButton(
                            .bestQuality,
                            detail: "Cleaner subject edges",
                            systemImage: "wand.and.stars"
                        )
                        qualityButton(
                            .flatBackground,
                            detail: "Flat-colour backdrops",
                            systemImage: "square.filled.on.square"
                        )
                    }

                    if engine == .bestQuality {
                        ModelInstallRow(installer: installer, model: .birefnet)
                    }

                    if engine == .flatBackground {
                        LabeledSlider(
                            title: "Strength",
                            reading: "\(Int(model.cutoutStrength * 100))%",
                            value: $model.cutoutStrength
                        )
                    }
                }

                section("Save to") {
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
                    .help(model.customDestinationURL?.path ?? "Save beside each original")

                    if let warning = model.destinationWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Toggle("Overwrite PNG originals when possible", isOn: $model.overwriteOriginals)
                        .controlSize(.small)

                    Toggle(
                        "Process new images automatically",
                        isOn: Binding(
                            get: { model.isWatchingFolder },
                            set: { model.setWatchingFolder($0) }
                        )
                    )
                    .controlSize(.small)

                    if model.isWatchingFolder {
                        folderRow(
                            "Watching",
                            name: model.watchedFolderURL?.lastPathComponent,
                            icon: "eye",
                            help: model.watchedFolderURL?.path
                        ) {
                            model.chooseWatchedFolder()
                        }
                        if let message = model.watcherMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                SourceActionSettings(model: model)
            }
        }
        .sheet(item: $editingItem) { item in
            CutoutEditorView(
                item: item,
                engine: $engine,
                removeBackground: { source, strength in
                    try await model.makeCutout(from: source, strength: strength)
                },
                onSaved: { url in model.acceptEditedResult(id: item.id, url: url) }
            )
        }
        .onAppear { model.operation = .cutout(engine: engine) }
        .onChange(of: engine) { _, newValue in model.operation = .cutout(engine: newValue) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The destination folder can change behind the app's back.
            model.refreshExistingResults()
        }
    }

    private func qualityButton(
        _ option: CompanionBatchModel.CutoutEngine,
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
        .help(option.explanation)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
