import Foundation

/// How to start the local reconstruction worker.
///
/// Two strategies, in priority order:
///
/// 1. **Bundled** — a Python runtime and the worker shipped inside the app at
///    `Contents/Resources/sculptor-engine/`. This is the only strategy that
///    works under the App Sandbox, because a sandboxed process may only execute
///    binaries inside its own bundle. It is what a release must use.
/// 2. **Developer-provided** — an interpreter chosen with `SCULPTOR_WORKER_PYTHON`
///    or in Settings, pointed at a checkout of `tools/sculptor-engine`. This is
///    how the app is run during development, before the runtime is packaged.
///
/// The split is why the Sculptor target is not sandboxed yet; see `project.yml`.
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

    /// Resolves a launch configuration, preferring a bundled runtime.
    ///
    /// - Returns: `nil` when no worker can be found, so the caller can explain
    ///   what is missing rather than failing at spawn time.
    public static func resolve(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> WorkerLaunchConfiguration? {
        if let bundled = bundled(in: bundle, fileManager: fileManager) {
            return bundled
        }
        return developerProvided(
            defaults: defaults, environment: environment, fileManager: fileManager
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
            environment: ["PYTHONPATH": root.path]
        )
    }

    private static func developerProvided(
        defaults: UserDefaults,
        environment: [String: String],
        fileManager: FileManager
    ) -> WorkerLaunchConfiguration? {
        let pythonPath = environment[pythonEnvironmentKey]
            ?? defaults.string(forKey: pythonDefaultsKey)
        let sourcePath = environment[sourceEnvironmentKey]
            ?? defaults.string(forKey: sourceDefaultsKey)

        guard let pythonPath, let sourcePath else { return nil }
        guard fileManager.isExecutableFile(atPath: pythonPath) else { return nil }

        var childEnvironment = environment
        childEnvironment["PYTHONPATH"] = sourcePath
        // Unbuffered, so progress lines arrive as they happen rather than in a
        // burst when the pipe flushes.
        childEnvironment["PYTHONUNBUFFERED"] = "1"

        return WorkerLaunchConfiguration(
            executable: URL(fileURLWithPath: pythonPath),
            arguments: ["-m", "sculptor_engine", "--serve"],
            environment: childEnvironment
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
