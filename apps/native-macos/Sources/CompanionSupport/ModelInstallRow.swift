import SwiftUI

struct ModelInstallRow: View {
    @ObservedObject var installer: ModelInstaller
    let model: CoreMLModel
    @State private var isHovering = false

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
        .onHover { isHovering = $0 }
    }

    @ViewBuilder private var action: some View {
        switch installer.state(model) {
        case .ready:
            HStack(spacing: 8) {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if isHovering {
                    Button {
                        installer.choosePackage(for: model)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Choose a replacement model")
                    .accessibilityLabel("Replace model")
                }
            }
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
