import XCTest

@testable import ImageKidSculptorKit

/// How the app decides which interpreter to run the worker with.
///
/// The bundled runtime must always win: it is the only strategy that works
/// under the App Sandbox, so a developer override left in `UserDefaults` must
/// never quietly take precedence in a shipped build.
final class WorkerLaunchConfigurationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// An executable stand-in for a Python interpreter.
    private func makeExecutable(named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path
        )
        return url
    }

    private var emptyDefaults: UserDefaults {
        UserDefaults(suiteName: "sculptor.tests.\(UUID().uuidString)")!
    }

    func testReturnsNilWhenNothingIsConfigured() {
        XCTAssertNil(
            WorkerLaunchConfiguration.resolve(
                bundle: Bundle(for: Self.self),
                defaults: emptyDefaults,
                environment: [:],
                searchRoots: []
            ),
            "an unconfigured app must report no worker rather than guess a path"
        )
    }

    func testUsesTheEnvironmentOverride() throws {
        let python = try makeExecutable(named: "python3")
        let configuration = try XCTUnwrap(
            WorkerLaunchConfiguration.resolve(
                bundle: Bundle(for: Self.self),
                defaults: emptyDefaults,
                environment: [
                    WorkerLaunchConfiguration.pythonEnvironmentKey: python.path,
                    WorkerLaunchConfiguration.sourceEnvironmentKey: directory.path
                ],
                searchRoots: []
            )
        )
        XCTAssertEqual(configuration.executable.path, python.path)
        XCTAssertEqual(configuration.arguments, ["-m", "sculptor_engine", "--serve"])
        XCTAssertEqual(configuration.environment?["PYTHONPATH"], directory.path)
        // Buffered output would make progress arrive in bursts at the end.
        XCTAssertEqual(configuration.environment?["PYTHONUNBUFFERED"], "1")
    }

    func testFallsBackToUserDefaults() throws {
        let python = try makeExecutable(named: "python3")
        let defaults = emptyDefaults
        defaults.set(python.path, forKey: WorkerLaunchConfiguration.pythonDefaultsKey)
        defaults.set(directory.path, forKey: WorkerLaunchConfiguration.sourceDefaultsKey)

        let configuration = try XCTUnwrap(
            WorkerLaunchConfiguration.resolve(
                bundle: Bundle(for: Self.self),
                defaults: defaults,
                environment: [:],
                searchRoots: []
            )
        )
        XCTAssertEqual(configuration.executable.path, python.path)
    }

    func testRequiresBothThePythonAndTheSource() throws {
        let python = try makeExecutable(named: "python3")
        XCTAssertNil(
            WorkerLaunchConfiguration.resolve(
                bundle: Bundle(for: Self.self),
                defaults: emptyDefaults,
                environment: [
                    WorkerLaunchConfiguration.pythonEnvironmentKey: python.path
                ],
                searchRoots: []
            ),
            "an interpreter without the worker source cannot run anything"
        )
    }

    func testRejectsAnInterpreterThatIsNotExecutable() throws {
        let notExecutable = directory.appendingPathComponent("python3")
        try "not a program".write(to: notExecutable, atomically: true, encoding: .utf8)

        XCTAssertNil(
            WorkerLaunchConfiguration.resolve(
                bundle: Bundle(for: Self.self),
                defaults: emptyDefaults,
                environment: [
                    WorkerLaunchConfiguration.pythonEnvironmentKey: notExecutable.path,
                    WorkerLaunchConfiguration.sourceEnvironmentKey: directory.path
                ],
                searchRoots: []
            ),
            "a non-executable path must be rejected before spawn time"
        )
    }

    func testTheBundledRuntimeWinsOverADeveloperOverride() throws {
        // Build a fake bundle laid out the way a release is packaged.
        let bundleRoot = directory.appendingPathComponent("Fake.bundle", isDirectory: true)
        let runtimeBin = bundleRoot
            .appendingPathComponent("sculptor-engine", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(
            at: runtimeBin, withIntermediateDirectories: true
        )
        let bundledPython = runtimeBin.appendingPathComponent("python3")
        try "#!/bin/sh\nexit 0\n".write(
            to: bundledPython, atomically: true, encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: bundledPython.path
        )
        let bundle = try XCTUnwrap(Bundle(url: bundleRoot) ?? Bundle(path: bundleRoot.path))

        let override = try makeExecutable(named: "override-python")
        let configuration = try XCTUnwrap(
            WorkerLaunchConfiguration.resolve(
                bundle: bundle,
                defaults: emptyDefaults,
                environment: [
                    WorkerLaunchConfiguration.pythonEnvironmentKey: override.path,
                    WorkerLaunchConfiguration.sourceEnvironmentKey: directory.path
                ],
                searchRoots: []
            )
        )
        XCTAssertEqual(
            configuration.executable.path, bundledPython.path,
            "a stale developer override must not shadow the shipped runtime"
        )
    }

    /// Builds a plausible `tools/sculptor-engine` checkout with a venv.
    @discardableResult
    private func makeCheckout(under root: URL) throws -> URL {
        let source = root.appendingPathComponent("tools/sculptor-engine", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("sculptor_engine", isDirectory: true),
            withIntermediateDirectories: true
        )
        let bin = source.appendingPathComponent(".venv/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let python = bin.appendingPathComponent("python")
        try "#!/bin/sh\nexit 0\n".write(to: python, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: python.path
        )
        return python
    }

    func testDiscoversACheckoutWithoutAnyConfiguration() throws {
        // A developer should not have to run `defaults write` before the app
        // will start for the first time.
        let python = try makeCheckout(under: directory)

        let configuration = try XCTUnwrap(
            WorkerLaunchConfiguration.resolve(
                bundle: Bundle(for: Self.self),
                defaults: emptyDefaults,
                environment: [:],
                searchRoots: [directory.path]
            )
        )
        XCTAssertEqual(configuration.executable.path, python.path)
        XCTAssertEqual(
            configuration.environment?["PYTHONPATH"],
            directory.appendingPathComponent("tools/sculptor-engine").path
        )
    }

    func testDiscoveryWalksUpwardsFromADeepStartingPoint() throws {
        // A debug build runs from deep inside DerivedData, not the repo root.
        let python = try makeCheckout(under: directory)
        let deep = directory.appendingPathComponent("a/b/c/d", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)

        let configuration = try XCTUnwrap(
            WorkerLaunchConfiguration.resolve(
                bundle: Bundle(for: Self.self),
                defaults: emptyDefaults,
                environment: [:],
                searchRoots: [deep.path]
            )
        )
        XCTAssertEqual(configuration.executable.path, python.path)
    }

    func testDiscoveryIgnoresACheckoutWithNoVirtualEnvironment() throws {
        // Source without a venv cannot run the worker; claiming it could would
        // fail later and more confusingly.
        let source = directory.appendingPathComponent("tools/sculptor-engine")
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("sculptor_engine"),
            withIntermediateDirectories: true
        )

        XCTAssertNil(
            WorkerLaunchConfiguration.resolve(
                bundle: Bundle(for: Self.self),
                defaults: emptyDefaults,
                environment: [:],
                searchRoots: [directory.path]
            )
        )
    }

    func testAStaleDefaultFallsBackToDiscovery() throws {
        // A path that worked on another machine must not strand the app.
        let python = try makeCheckout(under: directory)
        let defaults = emptyDefaults
        defaults.set("/nonexistent/python", forKey: WorkerLaunchConfiguration.pythonDefaultsKey)
        defaults.set("/nonexistent/source", forKey: WorkerLaunchConfiguration.sourceDefaultsKey)

        let configuration = try XCTUnwrap(
            WorkerLaunchConfiguration.resolve(
                bundle: Bundle(for: Self.self),
                defaults: defaults,
                environment: [:],
                searchRoots: [directory.path]
            )
        )
        XCTAssertEqual(configuration.executable.path, python.path)
    }

    func testDiscoversTheRealCheckoutFromThisRepository() throws {
        // The point of discovery is that it works on a real machine, not only
        // on a synthetic tree. Tests run from the package directory, so this
        // exercises the upward walk against the actual repository.
        //
        // Skipped where the worker has no virtual environment — CI, or a fresh
        // clone before `python3 -m venv .venv`.
        let configuration = WorkerLaunchConfiguration.resolve(
            bundle: Bundle(for: Self.self),
            defaults: emptyDefaults,
            environment: [:],
            searchRoots: [FileManager.default.currentDirectoryPath]
        )
        try XCTSkipIf(
            configuration == nil,
            "no tools/sculptor-engine/.venv in this checkout"
        )
        let found = try XCTUnwrap(configuration)
        XCTAssertTrue(
            found.executable.path.hasSuffix("tools/sculptor-engine/.venv/bin/python"),
            "discovered an unexpected interpreter: \(found.executable.path)"
        )
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: found.executable.path)
        )
    }

    func testTheMissingWorkerMessageNamesBothVariables() {
        let explanation = WorkerLaunchConfiguration.missingWorkerExplanation
        XCTAssertTrue(explanation.contains(WorkerLaunchConfiguration.pythonEnvironmentKey))
        XCTAssertTrue(explanation.contains(WorkerLaunchConfiguration.sourceEnvironmentKey))
    }
}
