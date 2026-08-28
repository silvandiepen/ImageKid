import Foundation

/// Drives one image through the app's single path: pick, generate, inspect,
/// export.
///
/// Deliberately one job at a time. Batch conversion is explicitly out of scope
/// for V1; the point is to prove the smallest useful loop with one asset.
@MainActor
public final class SculptorSession: ObservableObject {
    public enum Phase: Equatable {
        case empty
        case ready
        case processing(stage: SculptorStage, fraction: Double)
        case finished(ResultMessage)
        /// `code` is `nil` for failures raised by the bridge rather than
        /// reported by the worker.
        case failed(message: String, recoverable: Bool, code: SculptorErrorCode?)

        public var isProcessing: Bool {
            if case .processing = self { return true }
            return false
        }
    }

    @Published public private(set) var phase: Phase = .empty
    /// The imported image. Never modified, never overwritten.
    @Published public private(set) var sourceURL: URL?
    @Published public private(set) var engineDetail: String?

    private let worker: SculptorWorker
    private let workspaceRoot: URL
    private var currentJobId: String?
    private var jobTask: Task<Void, Never>?
    private var lastOptions: SculptorOptions?

    public init(worker: SculptorWorker, workspaceRoot: URL? = nil) {
        self.worker = worker
        self.workspaceRoot = workspaceRoot ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageKidSculptor", isDirectory: true)
    }

    // MARK: - Import

    public func open(_ url: URL) {
        cancel()
        sourceURL = url
        phase = .ready
    }

    public func reset() {
        cancel()
        sourceURL = nil
        phase = .empty
    }

    // MARK: - Generate

    public func generate(options: SculptorOptions? = nil) {
        guard let sourceURL else { return }
        guard !phase.isProcessing else { return }
        // Remembered so a retry or regenerate reproduces the same settings
        // rather than silently falling back to defaults.
        lastOptions = options

        let jobId = UUID().uuidString
        currentJobId = jobId
        phase = .processing(stage: .preparingImage, fraction: 0)

        let workspace = workspaceRoot.appendingPathComponent(jobId, isDirectory: true)
        let request = GenerateRequest(
            jobId: jobId,
            sourcePath: sourceURL.path,
            workspace: workspace.path,
            options: options
        )

        jobTask = Task { [worker] in
            do {
                for try await event in await worker.generate(request) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .progress(let progress):
                        self.phase = .processing(
                            stage: progress.stage, fraction: progress.fraction
                        )
                    case .finished(let result):
                        self.phase = .finished(result)
                    }
                }
            } catch let error as SculptorWorkerError {
                // A cancelled job returns the user to the ready state with the
                // source still loaded, so they can retry without re-importing.
                if case .reported(.cancelled, _, _) = error {
                    self.phase = .ready
                } else {
                    var code: SculptorErrorCode?
                    if case .reported(let reported, _, _) = error { code = reported }
                    if case .engineUnavailable = error { code = .modelNotInstalled }
                    self.phase = .failed(
                        message: error.errorDescription ?? "Generation failed.",
                        recoverable: error.isRecoverable,
                        code: code
                    )
                }
            } catch {
                self.phase = .failed(
                    message: error.localizedDescription, recoverable: true, code: nil
                )
            }
            self.currentJobId = nil
        }
    }

    public func cancel() {
        if let currentJobId {
            Task { [worker] in await worker.cancel(jobId: currentJobId) }
        }
        jobTask?.cancel()
        jobTask = nil
        currentJobId = nil
        if phase.isProcessing { phase = sourceURL == nil ? .empty : .ready }
    }

    /// Runs again from the same source image, with the same settings.
    public func regenerate() {
        guard sourceURL != nil else { return }
        let options = lastOptions
        phase = .ready
        generate(options: options)
    }

    // MARK: - Export

    /// Default export name for the current source, per the doc's convention.
    public var suggestedExportName: String {
        guard let sourceURL else { return "model-3d.glb" }
        return sourceURL.deletingPathExtension().lastPathComponent + "-3d.glb"
    }

    /// Copies the generated GLB to a destination the user chose.
    ///
    /// The worker already wrote and validated the asset atomically inside the
    /// job workspace; this is the final copy out to user-selected storage.
    public func export(to destination: URL) throws {
        guard case .finished(let result) = phase else { return }
        let fileManager = FileManager.default
        let source = URL(fileURLWithPath: result.glbPath)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    // MARK: - Startup

    /// Starts the worker so the first generation does not pay for model load.
    public func warmUp() async {
        do {
            let ready = try await worker.start()
            engineDetail = ready.engineAvailable ? nil : ready.detail
        } catch {
            engineDetail = error.localizedDescription
        }
    }

    public func shutdown() async {
        await worker.shutdown()
    }
}
