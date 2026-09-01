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

    /// Label on the left, the folder itself as the control. Reads as one line per
    /// question instead of a heading and a button for each.
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
            subtitle: "Batch-remove backgrounds locally and save clean transparent PNGs.",
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
                section("Method") {
                    Picker("Method", selection: $engine) {
                        ForEach(CompanionBatchModel.CutoutEngine.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help(engine.explanation)

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

                section("Files") {
                    folderRow(
                        "Save to",
                        name: model.customDestinationURL?.lastPathComponent,
                        icon: "folder",
                        help: model.customDestinationURL?.path
                            ?? "Cutouts are saved here as PNG, so transparency stays real."
                    ) {
                        model.chooseDestinationFolder()
                    }

                    if let warning = model.destinationWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Toggle("Overwrite PNG originals when possible", isOn: $model.overwriteOriginals)

                    Toggle(
                        "Process new images automatically",
                        isOn: Binding(
                            get: { model.isWatchingFolder },
                            set: { model.setWatchingFolder($0) }
                        )
                    )

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
}
