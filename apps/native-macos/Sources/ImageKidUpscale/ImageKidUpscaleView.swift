import ImageKidInference
import SwiftUI

struct ImageKidUpscaleView: View {
    @ObservedObject var model: CompanionBatchModel
    @State private var scale = 2
    @State private var contentMode = UpscaleContentMode.automatic

    var body: some View {
        CompanionBatchShell(
            title: "ImageKid Upscale",
            subtitle: "Throw in a batch, pick a size, and make every image bigger on this Mac.",
            primaryActionTitle: "Generate Upscales",
            isProcessing: model.isProcessing,
            items: model.items,
            progress: model.overallProgress,
            acceptsDrop: model.addFiles,
            openFiles: model.openFiles,
            clearCompleted: model.clearCompleted,
            removeItem: model.removeItem,
            primaryAction: { model.generate(operation: .upscale(scale: scale, contentMode: contentMode)) },
            cancelAction: model.cancel
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scale")
                        .font(.headline)
                    Picker("Scale", selection: $scale) {
                        Text("2x").tag(2)
                        Text("4x").tag(4)
                        Text("8x").tag(8)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Image Type")
                        .font(.headline)
                    Picker("Image Type", selection: $contentMode) {
                        ForEach(UpscaleContentMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Destination")
                        .font(.headline)
                    Button {
                        model.chooseDestinationFolder()
                    } label: {
                        Label(model.customDestinationURL?.lastPathComponent ?? "Choose Folder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    Toggle("Overwrite originals when possible", isOn: $model.overwriteOriginals)
                }
            }
        }
    }
}
