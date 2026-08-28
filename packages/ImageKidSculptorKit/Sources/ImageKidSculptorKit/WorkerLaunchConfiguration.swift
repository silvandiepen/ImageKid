import Foundation

/// How to start the local reconstruction worker.
///
/// Two strategies, in priority order:
///
/// 1. **Bundled** — a Python runtime and the worker shipped inside the app at
///    `Contents/Resources/sculptor-engine/`. This is the only strategy that
///    works under the App Sandbox, because a sandboxed process may only execute
///    binaries inside its own bundle. It is what a release must use.
/// 2. **Developer-provided** — an interpreter chosen with `SCULPTOR_WORKER_PYTHON`,
///    in Settings, or discovered by walking up to a `tools/sculptor-engine`
///    checkout. This is how the app runs from Xcode, where nothing is packaged.
///
/// A release must use the first: the target is sandboxed, and a sandboxed
/// process may only execute binaries inside its own bundle. Build one with
/// `tools/sculptor-engine/scripts/bundle_runtime.sh`.
public struct WorkerLaunchConfiguration: Equatable, Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]?

    public init(executable: URL, arguments: [String], environment: [String: String]? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }

    /// Environment variable naming the interpreter to run the worker with.
    public static let pythonEnvironmentKey = "SCULPTOR_WORKER_PYTHON"

    /// Environment variable naming the `tools/sculptor-engine` checkout.
    public static let sourceEnvironmentKey = "SCULPTOR_WORKER_SOURCE"

    /// `UserDefaults` keys backing the same two settings.
    public static let pythonDefaultsKey = "SculptorWorkerPython"
    public static let sourceDefaultsKey = "SculptorWorkerSource"

    /// Directories to walk upwards from when looking for a worker checkout.
    ///
    /// Injectable so tests can pass `[]` and assert the unconfigured case
    /// without the surrounding repository being discovered.
    public static var defaultSearchRoots: [String] {
        [
            FileManager.default.currentDirectoryPath,
            Bundle.main.bundleURL.deletingLastPathComponent().path
        ]
    }

    /// Resolves a launch configuration, preferring a bundled runtime.
    ///
    /// - Returns: `nil` when no worker can be found, so the caller can explain
    ///   what is missing rather than failing at spawn time.
    public static func resolve(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        searchRoots: [String] = defaultSearchRoots
    ) -> WorkerLaunchConfiguration? {
        if let bundled = bundled(in: bundle, fileManager: fileManager) {
            return bundled
        }
        return developerProvided(
            defaults: defaults,
            environment: environment,
            fileManager: fileManager,
            searchRoots: searchRoots
        )
    }

    private static func bundled(
        in bundle: Bundle, fileManager: FileManager
    ) -> WorkerLaunchConfiguration? {
        guard let resources = bundle.resourceURL else { return nil }
        let root = resources.appendingPathComponent("sculptor-engine", isDirectory: true)
        let python = root.appendingPathComponent("bin/python3")
        guard fileManager.isExecutableFile(atPath: python.path) else { return nil }
        return WorkerLaunchConfiguration(
            executable: python,
            arguments: ["-m", "sculptor_engine", "--serve"],
            environment: [
                "PYTHONPATH": root.path,
                "SCULPTOR_MODELS_DIR": SculptorModel.modelsDirectory.path
            ]
        )
    }

    /// Looks for a worker checkout next to the running app.
    ///
    /// A development build lives deep inside DerivedData, so this walks up
    /// looking for `tools/sculptor-engine` with its own virtual environment.
    /// It saves every developer from a `defaults write` before first launch,
    /// and finds nothing in a shipped app, where the bundled runtime applies.
    private static func discoveredCheckout(
        fileManager: FileManager, searchRoots: [String]
    ) -> WorkerLaunchConfiguration? {
        for candidate in searchRoots {
            var directory = URL(fileURLWithPath: candidate)
            for _ in 0..<12 {
                let source = directory
                    .appendingPathComponent("tools/sculptor-engine", isDirectory: true)
                let python = source.appendingPathComponent(".venv/bin/python")
                if fileManager.isExecutableFile(atPath: python.path),
                   fileManager.fileExists(
                    atPath: source.appendingPathComponent("sculptor_engine").path
                   ) {
                    return configuration(python: python.path, source: source.path)
                }
                let parent = directory.deletingLastPathComponent()
                if parent == directory { break }
                directory = parent
            }
        }
        return nil
    }

    private static func configuration(
        python: String, source: String, environment: [String: String] = [:]
    ) -> WorkerLaunchConfiguration {
        var childEnvironment = environment
        childEnvironment["PYTHONPATH"] = source
        // Unbuffered, so progress lines arrive as they happen rather than in a
        // burst when the pipe flushes.
        childEnvironment["PYTHONUNBUFFERED"] = "1"
        // Tell the worker where the weights are rather than letting it guess.
        // Under the sandbox its idea of home is the app container, so the
        // App Group path it would derive itself does not exist.
        childEnvironment["SCULPTOR_MODELS_DIR"] = SculptorModel.modelsDirectory.path
        return WorkerLaunchConfiguration(
            executable: URL(fileURLWithPath: python),
            arguments: ["-m", "sculptor_engine", "--serve"],
            environment: childEnvironment
        )
    }

    private static func developerProvided(
        defaults: UserDefaults,
        environment: [String: String],
        fileManager: FileManager,
        searchRoots: [String]
    ) -> WorkerLaunchConfiguration? {
        let pythonPath = environment[pythonEnvironmentKey]
            ?? defaults.string(forKey: pythonDefaultsKey)
        let sourcePath = environment[sourceEnvironmentKey]
            ?? defaults.string(forKey: sourceDefaultsKey)

        guard let pythonPath, let sourcePath else {
            // Nothing configured: look for a checkout rather than giving up and
            // making the user edit defaults by hand.
            return discoveredCheckout(fileManager: fileManager, searchRoots: searchRoots)
        }
        guard fileManager.isExecutableFile(atPath: pythonPath) else {
            return discoveredCheckout(fileManager: fileManager, searchRoots: searchRoots)
        }
        return configuration(
            python: pythonPath, source: sourcePath, environment: environment
        )
    }

    /// What to tell the user when `resolve` returns `nil`.
    public static var missingWorkerExplanation: String {
        """
        No reconstruction engine was found. Set \(pythonEnvironmentKey) to a \
        Python interpreter with the worker's dependencies installed, and \
        \(sourceEnvironmentKey) to a checkout of tools/sculptor-engine.
        """
    }
}
