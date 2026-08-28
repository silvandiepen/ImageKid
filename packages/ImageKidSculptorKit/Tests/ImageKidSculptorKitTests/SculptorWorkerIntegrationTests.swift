import XCTest

@testable import ImageKidSculptorKit

/// Drives the real `tools/sculptor-engine` worker over a real pipe.
///
/// This is the test that proves the two halves actually agree: the Swift types
/// decode what Python emits, progress arrives in order, and a generation
/// produces files on disk. Nothing here is substituted.
///
/// Skipped unless the worker is configured, because it needs a Python
/// environment with the worker's dependencies:
///
///     SCULPTOR_WORKER_PYTHON=/path/to/.venv/bin/python \
///     SCULPTOR_WORKER_SOURCE=/path/to/tools/sculptor-engine \
///     swift test
///
/// A full generation additionally needs the model installed; without it the
/// worker reports `modelNotInstalled`, which these tests treat as a valid
/// outcome so they stay meaningful on a machine with no weights.
final class SculptorWorkerIntegrationTests: XCTestCase {
    private var launch: WorkerLaunchConfiguration?

    override func setUp() {
        super.setUp()
        let environment = ProcessInfo.processInfo.environment
        guard environment[WorkerLaunchConfiguration.pythonEnvironmentKey] != nil,
              environment[WorkerLaunchConfiguration.sourceEnvironmentKey] != nil
        else { return }
        launch = WorkerLaunchConfiguration.resolve(
            bundle: Bundle(for: Self.self), environment: environment
        )
    }

    private func requireWorker() throws -> WorkerLaunchConfiguration {
        try XCTSkipIf(launch == nil, "Worker not configured; see this file's comment.")
        return launch!
    }

    /// A clean cutout: an opaque block on transparency, like a Tiko asset.
    private func makeSourceImage() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("source.png")

        let size = 256
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSColor.systemOrange.setFill()
        NSRect(x: 64, y: 56, width: 128, height: 148).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw XCTSkip("could not build a test image") }
        try png.write(to: url)
        return url
    }

    func testWorkerStartsAndReportsItsEngine() async throws {
        let worker = SculptorWorker(launch: try requireWorker())
        defer { Task { await worker.shutdown() } }

        let ready = try await worker.start()
        XCTAssertEqual(ready.protocolVersion, 1, "protocol version drifted between halves")
        XCTAssertFalse(ready.engine.isEmpty)
        if !ready.engineAvailable {
            XCTAssertNotNil(
                ready.detail, "an unavailable engine must say why so the app can explain"
            )
        }
    }

    func testGenerationEitherProducesAnAssetOrSaysWhyNot() async throws {
        let launch = try requireWorker()
        let worker = SculptorWorker(launch: launch)
        defer { Task { await worker.shutdown() } }

        let ready = try await worker.start()
        let source = try makeSourceImage()
        let workspace = source.deletingLastPathComponent()
            .appendingPathComponent("work", isDirectory: true)

        let request = GenerateRequest(
            jobId: UUID().uuidString,
            sourcePath: source.path,
            workspace: workspace.path,
            // A small marching-cubes input keeps the test quick; the pipeline
            // exercised is identical.
            options: SculptorOptions(inputSize: 256)
        )

        var stages: [SculptorStage] = []
        var fractions: [Double] = []
        var result: ResultMessage?

        do {
            for try await event in await worker.generate(request) {
                switch event {
                case .progress(let progress):
                    if stages.last != progress.stage { stages.append(progress.stage) }
                    fractions.append(progress.fraction)
                case .finished(let finished):
                    result = finished
                }
            }
        } catch let error as SculptorWorkerError {
            guard case .reported(let code, _, _) = error else {
                if case .engineUnavailable = error {
                    throw XCTSkip("model not installed: \(error.errorDescription ?? "")")
                }
                throw error
            }
            if code == .modelNotInstalled {
                throw XCTSkip("model not installed; reconstruction cannot be exercised")
            }
            throw error
        }

        XCTAssertFalse(ready.engine.isEmpty)
        XCTAssertEqual(fractions, fractions.sorted(), "progress went backwards")
        XCTAssertEqual(
            stages.prefix(2), [.preparingImage, .isolatingObject],
            "the worker did not visit the early stages in order"
        )

        let finished = try XCTUnwrap(result, "no result message arrived")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: finished.glbPath),
            "the reported GLB does not exist"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: finished.previewPath),
            "the reported preview does not exist"
        )
        XCTAssertGreaterThan(finished.triangleCount, 0)
        XCTAssertEqual(finished.upAxis, "+Y")
        XCTAssertEqual(finished.originConvention, "bottomCentre")
    }

    func testAnalysisRatesAnImageWithoutReconstructingIt() async throws {
        let worker = SculptorWorker(launch: try requireWorker())
        defer { Task { await worker.shutdown() } }

        let source = try makeSourceImage()
        let started = Date()
        let analysis = try await worker.analyse(
            AnalyseRequest(requestId: UUID().uuidString, sourcePath: source.path)
        )

        // A clean cutout on transparency is the good case.
        XCTAssertEqual(analysis.suitability, .good)
        XCTAssertTrue(analysis.hadMask)
        XCTAssertGreaterThan(analysis.subjectCoverage, 0)

        // The whole point is that it is cheap enough to run on import, so it
        // must not have loaded weights or reconstructed anything.
        XCTAssertLessThan(
            Date().timeIntervalSince(started), 5,
            "analysis should be near-instant; it must not touch the engine"
        )
    }

    func testAnalysisWorksEvenWhenTheModelIsNotInstalled() async throws {
        // Knowing an image is a poor candidate is most useful *before* the
        // user downloads gigabytes of weights.
        let worker = SculptorWorker(launch: try requireWorker())
        defer { Task { await worker.shutdown() } }

        let source = try makeSourceImage()
        let analysis = try await worker.analyse(
            AnalyseRequest(requestId: UUID().uuidString, sourcePath: source.path)
        )
        XCTAssertFalse(analysis.suitability.title.isEmpty)
    }

    func testAMissingSourceImageIsReportedAsARecoverableError() async throws {
        let worker = SculptorWorker(launch: try requireWorker())
        defer { Task { await worker.shutdown() } }
        _ = try await worker.start()

        let request = GenerateRequest(
            jobId: UUID().uuidString,
            sourcePath: "/nonexistent/nope.png",
            workspace: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
        )

        do {
            for try await _ in await worker.generate(request) {}
            XCTFail("expected a failure for a missing source image")
        } catch let error as SculptorWorkerError {
            guard case .reported(let code, _, _) = error else {
                if case .engineUnavailable = error { throw XCTSkip("model not installed") }
                throw error
            }
            XCTAssertEqual(code, .corruptImage)
        }
    }
}
