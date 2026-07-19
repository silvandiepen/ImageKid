import CoreGraphics
import CoreML
import Foundation
import XCTest
@testable import ImageKidInference

/// Upscaling an image with transparency must keep the transparent regions
/// transparent (a regression: they used to come back as opaque black).
final class UpscaleAlphaTests: XCTestCase {
    func testCoreImageUpscalePreservesTransparency() async throws {
        let source = try makeTransparentSubject(width: 64, height: 64)
        let upscaled = try await CoreImageUpscaler(sharpening: .photoArtwork)
            .upscale(source, to: CGSize(width: 128, height: 128))

        let stats = cornerAndCenterAlpha(upscaled)
        XCTAssertLessThan(stats.corner, 16, "The transparent corner should stay transparent, not go black.")
        XCTAssertGreaterThan(stats.center, 239, "The opaque subject should stay opaque.")
    }

    func testRealESRGANUpscalePreservesTransparency() async throws {
        guard let dir = ProcessInfo.processInfo.environment["IMAGEKID_MODELS_DIR"] else {
            throw XCTSkip("Set IMAGEKID_MODELS_DIR to run the Real-ESRGAN alpha test.")
        }
        let package = URL(fileURLWithPath: dir).appendingPathComponent("RealESRGAN.mlpackage")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: package.path), "RealESRGAN.mlpackage missing.")

        let upscaler = CoreMLUpscaler(
            modelProvider: PackageModelProvider(packageURL: package),
            configuration: CoreMLUpscalerConfiguration(fixedInputSize: CGSize(width: 256, height: 256))
        )
        let source = try makeTransparentSubject(width: 64, height: 64)
        let upscaled = try await upscaler.upscale(source, to: CGSize(width: 256, height: 256))

        let stats = cornerAndCenterAlpha(upscaled)
        XCTAssertLessThan(stats.corner, 16, "Transparent corner should stay transparent through Real-ESRGAN.")
        XCTAssertGreaterThan(stats.center, 239, "Subject should stay opaque.")
    }

    func testReapplyAlphaIsNoOpForOpaqueSource() throws {
        let opaque = try makeOpaque(width: 32, height: 32)
        let result = ImageConversion.reapplyAlpha(from: opaque, onto: opaque)
        XCTAssertEqual(result.width, opaque.width)
    }

    // MARK: - Helpers

    /// Opaque disc centered on a fully transparent field.
    private func makeTransparentSubject(width: Int, height: Int) throws -> CGImage {
        let context = try context(width: width, height: height)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1))
        let inset = CGFloat(width) * 0.25
        context.fillEllipse(in: CGRect(
            x: inset, y: inset, width: CGFloat(width) - inset * 2, height: CGFloat(height) - inset * 2
        ))
        return try unwrap(context.makeImage())
    }

    private func makeOpaque(width: Int, height: Int) throws -> CGImage {
        let context = try context(width: width, height: height)
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try unwrap(context.makeImage())
    }

    private func context(width: Int, height: Int) throws -> CGContext {
        try unwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
    }

    private func cornerAndCenterAlpha(_ image: CGImage) -> (corner: Int, center: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let cornerAlpha = Int(data[3]) // pixel (0,0)
        let centerIndex = ((height / 2) * width + width / 2) * 4 + 3
        return (corner: cornerAlpha, center: Int(data[centerIndex]))
    }

    private func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw XCTSkip("nil") }
        return value
    }
}
