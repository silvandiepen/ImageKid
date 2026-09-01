import SwiftUI

/// The "When Done" sidebar section: what happens to the input files once their result
/// is written. Shared by both companion apps so the behaviour and the wording match.
struct SourceActionSettings: View {
    @ObservedObject var model: CompanionBatchModel

    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When Done")
                .font(.headline)

            Picker("When Done", selection: action) {
                ForEach(SourceFileAction.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .disabled(model.isProcessing)

            if model.sourceAction.needsFolder {
                Button {
                    model.chooseSourceActionFolder()
                } label: {
                    Label(
                        model.sourceActionFolderURL?.lastPathComponent ?? "Choose Folder",
                        systemImage: "tray.and.arrow.down"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(model.isProcessing)
            }

            if let warning = model.sourceAction.warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(model.sourceAction == .delete ? .red : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.sourceAction != .keep, model.overwriteOriginals {
                Text("Skipped for images written back over the original \u{2014} there the original is the result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog(
            "Delete the originals after processing?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Originals", role: .destructive) { model.sourceAction = .delete }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each original is erased as soon as its result is written. It does not go to the "
                + "Trash and cannot be recovered. The setting is not remembered after you quit.")
        }
    }

    /// Arming the irreversible option asks first; everything else applies straight away.
    private var action: Binding<SourceFileAction> {
        Binding(
            get: { model.sourceAction },
            set: { selected in
                if selected == .delete {
                    isConfirmingDelete = true
                } else {
                    model.sourceAction = selected
                }
            }
        )
    }
}
