import CoreGraphics
import CoreImage
import CoreML
import XCTest
@testable import ImageKidInference

/// Runs the real converted Core ML models end-to-end. These are opt-in: set
/// `IMAGEKID_MODELS_DIR` to a folder containing `RealESRGAN.mlpackage` and
/// `ISNet.mlpackage` (e.g. `tools/coreml-conversion/out`). Without it, the tests
/// skip so ordinary CI stays model-free.
final class CoreMLModelIntegrationTests: XCTestCase {
    private var modelsDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["IMAGEKID_MODELS_DIR"] else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func testRealESRGANUpscalesToFourTimes() async throws {
        guard let modelsDirectory else {
            throw XCTSkip("Set IMAGEKID_MODELS_DIR to run the Core ML upscale test.")
        }
        let package = modelsDirectory.appendingPathComponent("RealESRGAN.mlpackage")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: package.path),
            "RealESRGAN.mlpackage not found in IMAGEKID_MODELS_DIR."
        )

        let provider = PackageModelProvider(packageURL: package)
        let upscaler = CoreMLUpscaler(
            modelProvider: provider,
            configuration: CoreMLUpscalerConfiguration(fixedInputSize: CGSize(width: 256, height: 256))
        )

        let source = try makeTestImage(width: 96, height: 64)
        let target = CGSize(width: 96 * 4, height: 64 * 4)
        let output = try await upscaler.upscale(source, to: target)

        XCTAssertEqual(output.width, 384, "Upscaled width should be 4×.")
        XCTAssertEqual(output.height, 256, "Upscaled height should be 4×.")
    }

    func testBiRefNetProducesTransparentBackground() async throws {
        guard let modelsDirectory else {
            throw XCTSkip("Set IMAGEKID_MODELS_DIR to run the Core ML background test.")
        }
        let package = modelsDirectory.appendingPathComponent("BiRefNet.mlpackage")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: package.path),
            "BiRefNet.mlpackage not found in IMAGEKID_MODELS_DIR."
        )

        // BiRefNet must run on the CPU (fp32); the Neural Engine/GPU overflow fp16
        // on its Swin backbone and return NaNs that wipe the mask.
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let provider = PackageModelProvider(packageURL: package, configuration: configuration)
        let remover = CoreMLBackgroundRemover(modelProvider: provider)

        // A filled disc on a flat field — a clear foreground subject.
        let source = try makeSubjectImage(width: 256, height: 256)
        let output = try await remover.removeBackground(from: source)

        XCTAssertEqual(output.width, source.width)
        XCTAssertEqual(output.height, source.height)

        // A correct cutout of a subject on a flat field has both transparent
        // (background) and opaque (subject) regions, and a full 0…255 alpha range.
        let stats = alphaStats(output)
        XCTAssertEqual(stats.min, 0, "Background pixels should be fully transparent.")
        XCTAssertEqual(stats.max, 255, "Subject pixels should be fully opaque.")
        XCTAssertGreaterThan(stats.transparentPct, 5, "Some background should be removed.")
        XCTAssertGreaterThan(stats.opaquePct, 5, "The subject should be kept.")
    }

    // MARK: - Helpers

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.1, alpha: 1))
        context.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        return try unwrap(context.makeImage())
    }

    private func makeSubjectImage(width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1))
        let inset = CGFloat(width) * 0.2
        context.fillEllipse(in: CGRect(x: inset, y: inset, width: CGFloat(width) - inset * 2, height: CGFloat(height) - inset * 2))
        return try unwrap(context.makeImage())
    }

    private func makeContext(width: Int, height: Int) throws -> CGContext {
        try unwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
    }

    private func alphaStats(_ image: CGImage) -> (min: Int, max: Int, transparentPct: Int, opaquePct: Int) {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (-1, -1, -1, -1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var lo = 255, hi = 0, transparent = 0, opaque = 0, total = 0
        for index in stride(from: 3, to: data.count, by: 4) {
            let a = Int(data[index])
            lo = min(lo, a); hi = max(hi, a)
            if a < 16 { transparent += 1 }
            if a > 239 { opaque += 1 }
            total += 1
        }
        let denom = max(total, 1)
        return (lo, hi, transparent * 100 / denom, opaque * 100 / denom)
    }

    private func unwrap<T>(_ value: T?, _ message: String = "Unexpected nil") throws -> T {
        guard let value else { throw XCTSkip(message) }
        return value
    }
}
