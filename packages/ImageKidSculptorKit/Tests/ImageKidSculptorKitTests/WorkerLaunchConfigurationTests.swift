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
                bundle: Bundle(for: Self.self), defaults: emptyDefaults, environment: [:]
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
                ]
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
                bundle: Bundle(for: Self.self), defaults: defaults, environment: [:]
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
                ]
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
                ]
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
                ]
            )
        )
        XCTAssertEqual(
            configuration.executable.path, bundledPython.path,
            "a stale developer override must not shadow the shipped runtime"
        )
    }

    func testTheMissingWorkerMessageNamesBothVariables() {
        let explanation = WorkerLaunchConfiguration.missingWorkerExplanation
        XCTAssertTrue(explanation.contains(WorkerLaunchConfiguration.pythonEnvironmentKey))
        XCTAssertTrue(explanation.contains(WorkerLaunchConfiguration.sourceEnvironmentKey))
    }
}
