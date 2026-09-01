import CoreGraphics
import XCTest
@testable import ImageKidInference

final class FlatBackgroundRemoverTests: XCTestCase {
    /// The case a saliency model gets wrong: a second, unconnected subject region that
    /// does not look like "the subject". The flood never reaches it, so it survives.
    func testKeepsAnIslandOfColourTheFloodCannotReach() async throws {
        let image = try makeImage(size: 16) { context in
            context.setFillColor(red: 0.95, green: 0.94, blue: 0.9, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            context.setFillColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1)
            context.fill(CGRect(x: 4, y: 4, width: 8, height: 8))
        }

        let cutout = try await FlatBackgroundRemover().removeBackground(from: image, progress: nil)
        let alpha = try alphaChannel(of: cutout, size: 16)

        XCTAssertEqual(Int(alpha[0]), 0, "the corner is backdrop")
        XCTAssertEqual(Int(alpha[8 * 16 + 8]), 255, "the subject is kept")
    }

    /// Backdrop colour enclosed by the subject is not backdrop, and a flood from the
    /// border cannot reach it.
    func testKeepsEnclosedBackdropColour() async throws {
        let image = try makeImage(size: 16) { context in
            context.setFillColor(red: 0.95, green: 0.94, blue: 0.9, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            context.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
            context.fill(CGRect(x: 3, y: 3, width: 10, height: 10))
            context.setFillColor(red: 0.95, green: 0.94, blue: 0.9, alpha: 1)
            context.fill(CGRect(x: 6, y: 6, width: 4, height: 4))
        }

        let cutout = try await FlatBackgroundRemover().removeBackground(from: image, progress: nil)
        let alpha = try alphaChannel(of: cutout, size: 16)

        XCTAssertEqual(Int(alpha[0]), 0)
        XCTAssertEqual(Int(alpha[8 * 16 + 8]), 255, "the hole keeps its pixels")
    }

    func testToleranceDecidesHowCloseCountsAsBackdrop() async throws {
        let image = try makeImage(size: 16) { context in
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            // A near-white band reaching the edge: backdrop only at a loose tolerance.
            context.setFillColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1)
            context.fill(CGRect(x: 0, y: 6, width: 16, height: 4))
        }

        let tight = try await FlatBackgroundRemover(tolerance: 0.01)
            .removeBackground(from: image, progress: nil)
        let loose = try await FlatBackgroundRemover(tolerance: 0.3)
            .removeBackground(from: image, progress: nil)

        let index = 8 * 16 + 8
        XCTAssertEqual(Int(try alphaChannel(of: tight, size: 16)[index]), 255)
        XCTAssertEqual(Int(try alphaChannel(of: loose, size: 16)[index]), 0)
    }

    // MARK: - Helpers

    private func makeImage(size: Int, draw: (CGContext) -> Void) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        draw(context)
        return try XCTUnwrap(context.makeImage())
    }

    private func alphaChannel(of image: CGImage, size: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let context = try XCTUnwrap(pixels.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        })
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}
