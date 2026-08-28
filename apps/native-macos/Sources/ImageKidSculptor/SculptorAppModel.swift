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
        // Most of this product's source images are isometric catalogue assets,
        // so that is the more useful default than eye level.
        self.viewpoint = defaults.string(forKey: Self.viewpointKey)
            .flatMap(SourceViewpoint.init(rawValue:)) ?? .overhead

        if let launch = WorkerLaunchConfiguration.resolve() {
            session = SculptorSession(worker: SculptorWorker(launch: launch))
        } else {
            // Still construct a session so the UI has something to bind to; it
            // will fail loudly if a generation is attempted.
            let fallback = WorkerLaunchConfiguration(
                executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: []
            )
            session = SculptorSession(worker: SculptorWorker(launch: fallback))
            setupProblem = WorkerLaunchConfiguration.missingWorkerExplanation
        }

        // SculptorSession is its own ObservableObject; forward its changes so
        // views observing this model redraw.
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
