import SwiftUI

struct ImageKidCutoutView: View {
    @ObservedObject var model: CompanionBatchModel

    var body: some View {
        CompanionBatchShell(
            title: "ImageKid Cutout",
            subtitle: "Batch-remove backgrounds locally and save clean transparent PNGs.",
            primaryActionTitle: "Generate Cutouts",
            isProcessing: model.isProcessing,
            items: model.items,
            progress: model.overallProgress,
            acceptsDrop: model.addFiles,
            openFiles: model.openFiles,
            clearCompleted: model.clearCompleted,
            removeItem: model.removeItem,
            primaryAction: { model.generate(operation: .cutout) },
            cancelAction: model.cancel
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Output")
                        .font(.headline)
                    Text("Cutouts are saved as PNG so transparency stays real.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Toggle("Overwrite PNG originals when possible", isOn: $model.overwriteOriginals)
                }
            }
        }
    }
}
