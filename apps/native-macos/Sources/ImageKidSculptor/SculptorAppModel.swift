import AppKit
import Combine
import ImageKidSculptorKit
import SwiftUI
import UniformTypeIdentifiers

/// App-level glue: file panels, the session, and the model download.
@MainActor
final class SculptorAppModel: ObservableObject {
    @Published private(set) var session: SculptorSession
    @Published var downloader = SculptorModelDownloader()
    /// Set when no worker could be located at all, which is a setup problem
    /// rather than something the user can fix in the app.
    @Published private(set) var setupProblem: String?

    private var cancellables: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Eye level, because it is the safe wrong answer. Surveying the Tiko
        // Media catalogue: 405 landmarks are isometric dioramas, but 263
        // animals and 222 people are eye-level three-quarter views, and an
        // imported photo is eye level too. Applying -60 to an eye-level subject
        // actively topples it, while leaving an isometric one uncorrected is
        // the same tilt the engine already produced.
        self.viewpoint = defaults.string(forKey: Self.viewpointKey)
            .flatMap(SourceViewpoint.init(rawValue:)) ?? .eyeLevel

        session = Self.makeSession()
        setupProblem = WorkerLaunchConfiguration.resolve() == nil
            ? WorkerLaunchConfiguration.missingWorkerExplanation
            : nil
        observe()
    }

    private static func makeSession() -> SculptorSession {
        guard let launch = WorkerLaunchConfiguration.resolve() else {
            // Still construct a session so the UI has something to bind to; it
            // will fail loudly if a generation is attempted.
            let fallback = WorkerLaunchConfiguration(
                executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: []
            )
            return SculptorSession(worker: SculptorWorker(launch: fallback))
        }
        return SculptorSession(worker: SculptorWorker(launch: launch))
    }

    /// Rebuilds the session against a newly chosen interpreter.
    ///
    /// The old worker is shut down rather than left running: it holds model
    /// weights in memory and a child process that nothing would reap.
    private func rebuildSession() {
        let previous = session
        Task { await previous.shutdown() }

        cancellables.removeAll()
        session = Self.makeSession()
        setupProblem = WorkerLaunchConfiguration.resolve() == nil
            ? WorkerLaunchConfiguration.missingWorkerExplanation
            : nil
        observe()
        Task { await session.warmUp() }
    }

    /// `SculptorSession` and the downloader are their own `ObservableObject`s;
    /// forward their changes so views observing this model redraw.
    private func observe() {
        session.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        downloader.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var isModelInstalled: Bool { downloader.isInstalled }

    var canExport: Bool {
        if case .finished = session.phase { return true }
        return false
    }

    func warmUp() async {
        guard setupProblem == nil else { return }
        await session.warmUp()
    }

    // MARK: - Engine location

    /// True once the Python runtime ships inside the app, at which point the
    /// engine settings are irrelevant.
    var hasBundledRuntime: Bool {
        guard let resources = Bundle.main.resourceURL else { return false }
        return FileManager.default.isExecutableFile(
            atPath: resources.appendingPathComponent("sculptor-engine/bin/python3").path
        )
    }

    var hasManualWorker: Bool {
        defaults.string(forKey: WorkerLaunchConfiguration.pythonDefaultsKey) != nil
    }

    var workerDescription: String? {
        WorkerLaunchConfiguration.resolve()?.executable.path
    }

    /// Lets the user point at an interpreter rather than editing defaults by
    /// hand. The worker checkout is inferred from it, since the two always sit
    /// together in a checkout.
    func chooseWorkerPython() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a Python interpreter with the worker's dependencies."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        defaults.set(url.path, forKey: WorkerLaunchConfiguration.pythonDefaultsKey)
        // .venv/bin/python -> the checkout two levels above bin.
        let inferred = url
            .deletingLastPathComponent()   // bin
            .deletingLastPathComponent()   // .venv
            .deletingLastPathComponent()   // checkout
        defaults.set(inferred.path, forKey: WorkerLaunchConfiguration.sourceDefaultsKey)
        rebuildSession()
    }

    func clearWorkerOverride() {
        defaults.removeObject(forKey: WorkerLaunchConfiguration.pythonDefaultsKey)
        defaults.removeObject(forKey: WorkerLaunchConfiguration.sourceDefaultsKey)
        rebuildSession()
    }

    // MARK: - Import

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose one image containing one clear object."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        session.open(url)
    }

    /// Accepts a dropped file. Returns false for anything that is not an image
    /// so the drop is rejected rather than silently ignored.
    func accept(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()),
              type.conforms(to: .image)
        else { return false }
        session.open(url)
        return true
    }

    // MARK: - Generate

    /// How the source image was seen. Remembered between launches because a
    /// user's library tends to be consistent.
    ///
    /// `@Published` over `UserDefaults` rather than `@AppStorage`: that wrapper
    /// only drives redraws from inside a `View`, so here the segmented picker
    /// would not visibly move when the selection changed.
    @Published var viewpoint: SourceViewpoint {
        didSet { defaults.set(viewpoint.rawValue, forKey: Self.viewpointKey) }
    }

    private static let viewpointKey = "SculptorSourceViewpoint"
    private let defaults: UserDefaults

    /// Starts a generation.
    ///
    /// The worker is the authority on whether the model is usable — it is the
    /// process that actually loads the weights. The app's own `isInstalled`
    /// check only drives hints in the UI; gating on it here would let the two
    /// disagree and refuse a generation the worker could have run.
    func generate() {
        session.generate(
            options: SculptorOptions(pitchCorrection: viewpoint.pitchCorrection)
        )
    }

    /// Runs again from the same image, picking up any viewpoint change.
    func regenerate() {
        generate()
    }

    // MARK: - Export

    func exportModel() {
        guard case .finished = session.phase else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "glb") ?? .data]
        panel.nameFieldStringValue = session.suggestedExportName
        panel.message = "Export the generated 3D model."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try session.export(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
