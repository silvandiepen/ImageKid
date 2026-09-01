import SwiftUI

struct ModelInstallRow: View {
    @ObservedObject var installer: ModelInstaller
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

            if case .installing = installer.state(model) {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var action: some View {
        switch installer.state(model) {
        case .ready:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .installing:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Button("Choose Again…") {
                installer.choosePackage(for: model)
            }
            .buttonStyle(.bordered)
        case .notInstalled:
            Button("Import…") {
                installer.choosePackage(for: model)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
