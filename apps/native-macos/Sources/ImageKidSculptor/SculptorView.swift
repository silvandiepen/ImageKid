import ImageKidSculptorKit
import SwiftUI
import UniformTypeIdentifiers

/// The whole app: one obvious path from image to 3D model.
struct SculptorView: View {
    @ObservedObject var model: SculptorAppModel
    @State private var isTargetedForDrop = false
    @State private var previewGeneration = 0
    @State private var hasDismissedSetupProblem = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.session.sourceURL != nil {
                Divider()
                actionBar
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers)
        }
        // A real binding, not `.constant`: an alert that cannot be dismissed
        // re-presents itself forever and locks the window.
        .alert(
            "Setup needed",
            isPresented: Binding(
                get: { model.setupProblem != nil && !hasDismissedSetupProblem },
                set: { presented in
                    if !presented { hasDismissedSetupProblem = true }
                }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(model.setupProblem ?? "") }
        )
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        switch model.session.phase {
        case .empty:
            emptyState
        case .ready:
            readyState
        case .processing(let stage, let fraction):
            processingState(stage: stage, fraction: fraction)
        case .finished(let result):
            resultState(result)
        case .failed(let message, let recoverable, let code):
            failureState(message: message, recoverable: recoverable, code: code)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Turn one image into a 3D model on your Mac.")
                .font(.title2)
            Text("Drop an image here, or choose one.")
                .foregroundStyle(.secondary)
            Button("Choose Image…") { model.chooseImage() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            if !model.isModelInstalled {
                modelInstallNotice
                    .padding(.top, 12)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropHighlight)
    }

    private var readyState: some View {
        VStack(spacing: 16) {
            sourcePreview
            suitabilityBadge
            viewpointPicker
            if !model.isModelInstalled {
                modelInstallNotice
            }
        }
        .padding(32)
    }

    /// How well this image suits single-image reconstruction.
    ///
    /// Advisory only — it never blocks Generate. Some subjects simply cannot
    /// work (a flag is a 2D graphic with no object to reconstruct), and saying
    /// so up front is kinder than a ten-second wait for a slab.
    @ViewBuilder
    private var suitabilityBadge: some View {
        if let analysis = model.session.analysis {
            VStack(spacing: 4) {
                Label(analysis.suitability.title, systemImage: badgeIcon(analysis.suitability))
                    .font(.callout)
                    .foregroundStyle(badgeColour(analysis.suitability))
                ForEach(analysis.notes, id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 460)
        }
    }

    private func badgeIcon(_ suitability: Suitability) -> String {
        switch suitability {
        case .good: "checkmark.circle"
        case .okay: "exclamationmark.circle"
        case .poor: "xmark.circle"
        }
    }

    private func badgeColour(_ suitability: Suitability) -> Color {
        switch suitability {
        case .good: .green
        case .okay: .orange
        case .poor: .red
        }
    }

    /// The source camera's height is the one thing that cannot be recovered
    /// from the image, and getting it wrong lays the model on its side.
    private var viewpointPicker: some View {
        VStack(spacing: 6) {
            Picker("Seen from", selection: Binding(
                get: { model.viewpoint },
                set: { model.viewpoint = $0 }
            )) {
                ForEach(SourceViewpoint.allCases) { viewpoint in
                    Text(viewpoint.title).tag(viewpoint)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Text(model.viewpoint.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func processingState(stage: SculptorStage, fraction: Double) -> some View {
        VStack(spacing: 24) {
            sourcePreview
                .opacity(0.5)
            VStack(spacing: 10) {
                Text(stage.title)
                    .font(.headline)
                    .contentTransition(.identity)
                ProgressView(value: fraction)
                    .frame(width: 320)
                Text("\(Int(fraction * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
    }

    private func resultState(_ result: ResultMessage) -> some View {
        VStack(spacing: 0) {
            ModelPreviewView(
                previewURL: URL(fileURLWithPath: result.previewPath),
                generation: previewGeneration
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { previewGeneration += 1 }

            HStack(spacing: 16) {
                Label(
                    "\(result.triangleCount.formatted()) triangles",
                    systemImage: "grid"
                )
                Label(
                    result.durationSeconds.formatted(
                        .number.precision(.fractionLength(1))
                    ) + "s",
                    systemImage: "clock"
                )
                Spacer()
                Text("Drag to rotate. Scroll to zoom.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func failureState(
        message: String, recoverable: Bool, code: SculptorErrorCode?
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            // A missing model is the one failure the app can fix itself.
            if code == .modelNotInstalled {
                modelInstallNotice
            } else if recoverable {
                Button("Try Again") { model.regenerate() }
                    .buttonStyle(.borderedProminent)
            }
            Button("Choose Another Image") { model.chooseImage() }
        }
        .padding(40)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var sourcePreview: some View {
        if let url = model.session.sourceURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 420, maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var modelInstallNotice: some View {
        VStack(spacing: 10) {
            switch model.downloader.state {
            case .notDownloaded:
                Text("The 3D model needs to be installed before generating.")
                    .foregroundStyle(.secondary)
                Button("Install Model (\(SculptorModel.triposr.approximateSize))") {
                    model.downloader.download()
                }
            case .downloading(let received, let expected):
                VStack(spacing: 6) {
                    Text("Installing the 3D model…")
                    ProgressView(
                        value: expected > 0 ? Double(received) / Double(expected) : 0
                    )
                    .frame(width: 280)
                    Text(
                        "\(ByteCountFormatter.string(fromByteCount: received, countStyle: .file))"
                        + " of "
                        + ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button("Cancel") { model.downloader.cancel() }
                }
            case .installing:
                ProgressView("Finishing installation…")
            case .ready:
                EmptyView()
            case .failed(let message):
                VStack(spacing: 6) {
                    Text("The model could not be installed.")
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Button("Try Again") { model.downloader.download() }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("Choose Another…") { model.chooseImage() }

            Spacer()

            if model.session.phase.isProcessing {
                Button("Cancel") { model.session.cancel() }
            } else if model.canExport {
                Button("Regenerate") {
                    previewGeneration += 1
                    model.regenerate()
                }
                Button("Export GLB…") { model.exportModel() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("e")
            } else {
                Button("Generate 3D") { model.generate() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.session.sourceURL == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if isTargetedForDrop {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding(20)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in _ = model.accept(url) }
        }
        return true
    }
}
