import ImageKidSculptorKit
import SwiftUI

/// Model status and disk usage, with a way to reclaim the space.
///
/// The doc requires this because Sculptor's weights are gigabytes rather than
/// the megabytes ImageKid's 2D add-ons need: storage has to be inspectable.
struct SculptorSettingsView: View {
    @ObservedObject var model: SculptorAppModel

    private let modelKind = SculptorModel.triposr

    var body: some View {
        Form {
            Section("3D model") {
                LabeledContent("Status") {
                    Text(model.isModelInstalled ? "Installed" : "Not installed")
                        .foregroundStyle(model.isModelInstalled ? .primary : .secondary)
                }
                LabeledContent("Disk usage") {
                    Text(
                        model.isModelInstalled
                            ? ByteCountFormatter.string(
                                fromByteCount: modelKind.installedBytes, countStyle: .file
                            )
                            : "—"
                    )
                }
                LabeledContent("Location") {
                    Text(modelKind.directory.path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                }
                HStack {
                    if model.isModelInstalled {
                        // Removing weights must never touch models the user
                        // has already generated and exported.
                        Button("Remove Model") { model.downloader.remove() }
                    } else {
                        Button("Install Model") { model.downloader.download() }
                    }
                    Spacer()
                }
            }

            // Only shown while the runtime is not packaged into the bundle.
            // Once it is, the app finds its own engine and this is noise.
            if !model.hasBundledRuntime {
                Section("Reconstruction engine") {
                    LabeledContent("Status") {
                        Text(model.setupProblem == nil ? "Found" : "Not found")
                            .foregroundStyle(model.setupProblem == nil ? .primary : .secondary)
                    }
                    if let path = model.workerDescription {
                        LabeledContent("Interpreter") {
                            Text(path)
                                .font(.caption)
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                    HStack {
                        Button("Choose Interpreter…") { model.chooseWorkerPython() }
                        if model.hasManualWorker {
                            Button("Use Automatic") { model.clearWorkerOverride() }
                        }
                        Spacer()
                    }
                    Text(
                        "Sculptor reconstructs in a separate process. A development "
                        + "build finds the checkout automatically; pick an interpreter "
                        + "only if it cannot."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Processing") {
                Text(
                    "Generation runs entirely on this Mac. Images are never "
                    + "uploaded, and no account or generation credits are needed. "
                    + "A network connection is used only to install the model."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
    }
}
