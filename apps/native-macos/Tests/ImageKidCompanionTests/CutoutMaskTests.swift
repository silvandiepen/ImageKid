import CoreGraphics
import XCTest

final class CutoutMaskTests: XCTestCase {
    func testMaskStartsFromTheCutoutAlpha() throws {
        let source = try makeOpaqueImage(width: 8, height: 8)
        let cutout = try makeTransparentImage(width: 8, height: 8)

        let mask = try XCTUnwrap(CutoutMask(source: source, cutout: cutout))
        let rendered = try XCTUnwrap(mask.render())

        XCTAssertEqual(try averageAlpha(of: rendered), 0, accuracy: 2)
    }

    func testMaskWithoutACutoutKeepsEverything() throws {
        let source = try makeOpaqueImage(width: 8, height: 8)

        let mask = try XCTUnwrap(CutoutMask(source: source, cutout: nil))
        let rendered = try XCTUnwrap(mask.render())

        XCTAssertEqual(try averageAlpha(of: rendered), 255, accuracy: 2)
    }

    func testRestoreBringsPixelsBackAndUndoTakesThemAway() throws {
        let source = try makeOpaqueImage(width: 8, height: 8)
        let cutout = try makeTransparentImage(width: 8, height: 8)
        let mask = try XCTUnwrap(CutoutMask(source: source, cutout: cutout))

        mask.beginStroke(diameter: 64, hardness: 1, tool: .restore)
        mask.paint(to: CGPoint(x: 4, y: 4))
        mask.endStroke()
        XCTAssertEqual(try averageAlpha(of: XCTUnwrap(mask.render())), 255, accuracy: 2)

        XCTAssertTrue(mask.canUndo)
        mask.undo()
        XCTAssertEqual(try averageAlpha(of: XCTUnwrap(mask.render())), 0, accuracy: 2)
        XCTAssertFalse(mask.canUndo)
    }

    func testEraseRemovesPixels() throws {
        let source = try makeOpaqueImage(width: 8, height: 8)
        let mask = try XCTUnwrap(CutoutMask(source: source, cutout: nil))

        mask.beginStroke(diameter: 64, hardness: 1, tool: .erase)
        mask.paint(to: CGPoint(x: 4, y: 4))
        mask.endStroke()

        XCTAssertEqual(try averageAlpha(of: XCTUnwrap(mask.render())), 0, accuracy: 2)
    }

    func testStrengthLiftsAndCrushesTheModelMask() throws {
        let source = try makeOpaqueImage(width: 8, height: 8)
        let halfCovered = try makeImage(width: 8, height: 8, alpha: 128)
        let mask = try XCTUnwrap(CutoutMask(source: source, cutout: halfCovered))

        XCTAssertEqual(try averageAlpha(of: XCTUnwrap(mask.render())), 128, accuracy: 3)

        mask.setStrength(0.25)
        XCTAssertEqual(try averageAlpha(of: XCTUnwrap(mask.render())), 255, accuracy: 3)

        mask.setStrength(0.75)
        XCTAssertEqual(try averageAlpha(of: XCTUnwrap(mask.render())), 0, accuracy: 3)
    }

    func testStrengthKeepsPaintedCorrections() throws {
        let source = try makeOpaqueImage(width: 8, height: 8)
        let cutout = try makeTransparentImage(width: 8, height: 8)
        let mask = try XCTUnwrap(CutoutMask(source: source, cutout: cutout))

        mask.beginStroke(diameter: 64, hardness: 1, tool: .restore)
        mask.paint(to: CGPoint(x: 4, y: 4))
        mask.endStroke()

        // Re-thresholding rebuilds the coverage; the stroke has to survive that.
        mask.setStrength(0.7)
        XCTAssertEqual(try averageAlpha(of: XCTUnwrap(mask.render())), 255, accuracy: 2)
    }

    func testRegionStrokeFollowsTheRegionBeyondTheBrush() throws {
        // Left half one colour, right half another. A stroke that touches only a few
        // pixels of the left half should take the whole half, and nothing of the right.
        let source = try makeTwoToneImage(size: 32)
        let mask = try XCTUnwrap(CutoutMask(source: source, cutout: nil))

        mask.beginStroke(diameter: 4, hardness: 1, tool: .erase, mode: .region, tolerance: 0.1)
        mask.paint(to: CGPoint(x: 4, y: 16))
        mask.endStroke()

        let alpha = try alphaChannel(of: XCTUnwrap(mask.render()), size: 32)
        XCTAssertEqual(Int(alpha[16 * 32 + 2]), 0, "the far side of the brushed region goes")
        XCTAssertEqual(Int(alpha[16 * 32 + 28]), 255, "the other colour stays")
    }

    /// The crash: a stroke that strays onto the subject seeds pixels far outside the
    /// tolerance, and the coverage ramp then computed past 255 and trapped.
    func testRegionStrokeSurvivesAStrokeThatCrossesTheBoundary() throws {
        let source = try makeTwoToneImage(size: 32)
        let mask = try XCTUnwrap(CutoutMask(source: source, cutout: nil))

        mask.beginStroke(diameter: 40, hardness: 1, tool: .erase, mode: .region, tolerance: 0.05)
        mask.paint(to: CGPoint(x: 4, y: 16))
        mask.paint(to: CGPoint(x: 28, y: 16))
        mask.endStroke()

        let alpha = try alphaChannel(of: XCTUnwrap(mask.render()), size: 32)
        XCTAssertEqual(alpha.count, 32 * 32)
    }

    /// The same gesture, the other way round: a region stroke set to Add Back brings a
    /// whole region into the cutout.
    func testRegionStrokeCanAddAWholeRegionBack() throws {
        let source = try makeTwoToneImage(size: 32)
        let cutout = try makeTransparentImage(width: 32, height: 32)
        let mask = try XCTUnwrap(CutoutMask(source: source, cutout: cutout))

        mask.beginStroke(diameter: 4, hardness: 1, tool: .restore, mode: .region, tolerance: 0.1)
        mask.paint(to: CGPoint(x: 4, y: 16))
        mask.endStroke()

        let alpha = try alphaChannel(of: XCTUnwrap(mask.render()), size: 32)
        XCTAssertEqual(Int(alpha[16 * 32 + 2]), 255, "the brushed region comes back whole")
        XCTAssertEqual(Int(alpha[16 * 32 + 28]), 0, "the other colour stays out")
    }

    func testRegionStrokeStaysUndoable() throws {
        let source = try makeTwoToneImage(size: 32)
        let mask = try XCTUnwrap(CutoutMask(source: source, cutout: nil))

        mask.beginStroke(diameter: 4, hardness: 1, tool: .erase, mode: .region, tolerance: 0.1)
        mask.paint(to: CGPoint(x: 4, y: 16))
        mask.endStroke()
        mask.undo()

        let alpha = try alphaChannel(of: XCTUnwrap(mask.render()), size: 32)
        XCTAssertEqual(Int(alpha[16 * 32 + 2]), 255)
    }

    private func makeTwoToneImage(size: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
        context.setFillColor(red: 0.9, green: 0.8, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: size / 2, y: 0, width: size / 2, height: size))
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

    // MARK: - Helpers

    private func makeOpaqueImage(width: Int, height: Int) throws -> CGImage {
        try makeImage(width: width, height: height, alpha: 255)
    }

    private func makeTransparentImage(width: Int, height: Int) throws -> CGImage {
        try makeImage(width: width, height: height, alpha: 0)
    }

    func makeImage(width: Int, height: Int, alpha: UInt8) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: CGFloat(alpha) / 255)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func averageAlpha(of image: CGImage) throws -> Double {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        })
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let alphas = stride(from: 3, to: pixels.count, by: 4).map { Double(pixels[$0]) }
        return alphas.reduce(0, +) / Double(alphas.count)
    }
}
