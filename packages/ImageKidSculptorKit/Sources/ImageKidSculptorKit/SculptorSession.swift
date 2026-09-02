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
    /// Rating of the imported image, once the worker has answered. `nil` while
    /// it is still being analysed, or if analysis failed — a missing rating
    /// must never block generating.
    @Published public private(set) var analysis: AnalysisMessage?

    private let worker: SculptorWorker
    private let workspaceRoot: URL
    private var currentJobId: String?
    private var jobTask: Task<Void, Never>?
    private var lastOptions: SculptorOptions?
    private var analysisTask: Task<Void, Never>?
    /// The worker-readable copy of the source image. See ``stageSource``.
    private var stagedURL: URL?

    /// Copies the source image somewhere the worker can read it.
    ///
    /// The worker is a separate process. A sandboxed app is granted access to a
    /// file the user opened — through the open panel, a drop, or Finder — but
    /// that grant does not reach a child process, so handing the worker the
    /// original path fails with "Operation not permitted" even though the app
    /// itself can read and display the image perfectly well.
    ///
    /// Staging it inside the workspace, which the app owns outright, sidesteps
    /// the whole question. It also means a generation is unaffected if the user
    /// moves or deletes the original while it runs.
    private func stageSource(_ url: URL) throws -> URL {
        let staging = workspaceRoot.appendingPathComponent("staged", isDirectory: true)
        try FileManager.default.createDirectory(
            at: staging, withIntermediateDirectories: true
        )
        let extensionName = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let staged = staging.appendingPathComponent(
            UUID().uuidString + "." + extensionName
        )

        // A security-scoped URL needs opening before it can be read; one that
        // is not scoped returns false here and is readable anyway.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if FileManager.default.fileExists(atPath: staged.path) {
            try FileManager.default.removeItem(at: staged)
        }
        try FileManager.default.copyItem(at: url, to: staged)
        return staged
    }

    public init(worker: SculptorWorker, workspaceRoot: URL? = nil) {
        self.worker = worker
        self.workspaceRoot = workspaceRoot ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageKidSculptor", isDirectory: true)
    }

    // MARK: - Import

    public func open(_ url: URL) {
        cancel()
        sourceURL = url
        analysis = nil
        stagedURL = try? stageSource(url)
        phase = .ready

        // Rate the image straight away, so a subject that cannot reconstruct
        // well — a flag, a cropped object — says so before the user waits out
        // a generation to find out.
        analysisTask?.cancel()
        guard let readable = stagedURL else { return }
        analysisTask = Task { [worker] in
            let rating = try? await worker.analyse(
                AnalyseRequest(requestId: UUID().uuidString, sourcePath: readable.path)
            )
            guard !Task.isCancelled, self.sourceURL == url else { return }
            self.analysis = rating
        }
    }

    public func reset() {
        cancel()
        analysisTask?.cancel()
        analysisTask = nil
        analysis = nil
        stagedURL = nil
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
        guard let staged = stagedURL ?? (try? stageSource(sourceURL)) else {
            phase = .failed(
                message: "Could not read the image.", recoverable: true, code: nil
            )
            return
        }
        let request = GenerateRequest(
            jobId: jobId,
            sourcePath: staged.path,
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

    /// Regenerates with export-specific settings and returns the new result.
    ///
    /// Detail and colour live in the mesh, so exporting at a different triangle
    /// count or without flat colour means asking the worker again rather than
    /// re-saving the file already on disk. The on-screen model is replaced by
    /// the new one, so what the user exported is what they are still looking
    /// at.
    public func regenerateForExport(options: SculptorOptions) async -> ResultMessage? {
        guard let sourceURL else { return nil }

        let jobId = UUID().uuidString
        let workspace = workspaceRoot.appendingPathComponent(jobId, isDirectory: true)
        guard let staged = stagedURL ?? (try? stageSource(sourceURL)) else {
            return nil
        }
        let request = GenerateRequest(
            jobId: jobId,
            sourcePath: staged.path,
            workspace: workspace.path,
            options: options
        )

        currentJobId = jobId
        phase = .processing(stage: .preparingImage, fraction: 0)
        defer { currentJobId = nil }

        do {
            for try await event in await worker.generate(request) {
                switch event {
                case .progress(let progress):
                    phase = .processing(stage: progress.stage, fraction: progress.fraction)
                case .finished(let result):
                    lastOptions = options
                    phase = .finished(result)
                    return result
                }
            }
        } catch let error as SculptorWorkerError {
            phase = .failed(
                message: error.errorDescription ?? "Export failed.",
                recoverable: error.isRecoverable,
                code: { if case .reported(let code, _, _) = error { return code }; return nil }()
            )
        } catch {
            phase = .failed(message: error.localizedDescription, recoverable: true, code: nil)
        }
        return nil
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
