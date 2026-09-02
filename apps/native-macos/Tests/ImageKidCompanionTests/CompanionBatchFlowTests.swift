import CoreGraphics
import XCTest

@MainActor
final class CompanionBatchFlowTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompanionBatchFlowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testChangingScaleRerunsAndOverwritesTheExistingResult() async throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("source.png")
        let destination = temporaryDirectory.appendingPathComponent("Results", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try CompanionImageIO.writePNG(try makeImage(width: 8, height: 6), to: sourceURL)

        let model = CompanionBatchModel()
        model.sourceAction = .keep
        model.customDestinationURL = destination
        model.operation = .upscale(scale: 2, contentMode: .photoArtwork, engine: .standard)
        model.addFiles([sourceURL])

        model.generate(existingResults: .overwrite)
        try await waitForBatch(model)

        let firstURL = try XCTUnwrap(model.items.first?.outputURL)
        XCTAssertEqual(CompanionImageIO.properties(at: firstURL)?.width, 16)
        XCTAssertEqual(CompanionImageIO.properties(at: firstURL)?.height, 12)
        XCTAssertEqual(model.items.first?.outputSizeLabel, "16 x 12 px")

        model.operation = .upscale(scale: 4, contentMode: .photoArtwork, engine: .standard)
        XCTAssertTrue(model.items.first?.wouldOverwriteExistingFile == true)
        model.generate(existingResults: .overwrite)
        try await waitForBatch(model)

        let secondURL = try XCTUnwrap(model.items.first?.outputURL)
        XCTAssertEqual(secondURL, firstURL, "a chosen overwrite must keep the planned path")
        XCTAssertEqual(CompanionImageIO.properties(at: secondURL)?.width, 32)
        XCTAssertEqual(CompanionImageIO.properties(at: secondURL)?.height, 24)
        XCTAssertEqual(model.items.first?.outputSizeLabel, "32 x 24 px")
        XCTAssertEqual(CompanionImageIO.properties(at: sourceURL)?.width, 8, "reruns use the original")
        XCTAssertEqual(CompanionImageIO.properties(at: sourceURL)?.height, 6)
    }

    func testSkipLeavesAnExistingResultUntouched() async throws {
        let sourceURL = temporaryDirectory.appendingPathComponent("source.png")
        let destination = temporaryDirectory.appendingPathComponent("Results", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try CompanionImageIO.writePNG(try makeImage(width: 5, height: 4), to: sourceURL)

        let existingURL = destination.appendingPathComponent("source.png")
        try CompanionImageIO.writePNG(try makeImage(width: 10, height: 8), to: existingURL)

        let model = CompanionBatchModel()
        model.sourceAction = .keep
        model.customDestinationURL = destination
        model.operation = .upscale(scale: 4, contentMode: .photoArtwork, engine: .standard)
        model.addFiles([sourceURL])

        model.generate(existingResults: .skip)

        XCTAssertFalse(model.isProcessing)
        XCTAssertEqual(model.items.first?.state, .skipped)
        XCTAssertEqual(CompanionImageIO.properties(at: existingURL)?.width, 10)
        XCTAssertEqual(CompanionImageIO.properties(at: existingURL)?.height, 8)
    }

    private func waitForBatch(_ model: CompanionBatchModel) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while model.isProcessing, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(model.isProcessing, "batch did not finish before the test deadline")
        if case .failed(let message) = model.items.first?.state {
            XCTFail("batch failed: \(message)")
        }
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
