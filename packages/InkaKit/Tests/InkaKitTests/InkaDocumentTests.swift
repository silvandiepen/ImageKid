import BrushKit
import CoreGraphics
import ImageIO
import XCTest

@testable import InkaKit

final class InkaDocumentTests: XCTestCase {

    private func sampleStroke() -> BrushStroke {
        let input = StrokeInput(samples: [
            StrokeSample(position: CGPoint(x: 20, y: 60), pressure: 0.4),
            StrokeSample(position: CGPoint(x: 200, y: 60), pressure: 1),
        ])
        return BrushStroke(brushID: BrushLibrary.inkPen.id, color: RGBA(r: 0, g: 0, b: 0), input: input)
    }

    func testBlankDocumentHasOneStrokeLayer() {
        let doc = InkaDocument.blank(width: 256, height: 128)
        XCTAssertEqual(doc.layers.count, 1)
        XCTAssertTrue(doc.layers[0].isVector)
        XCTAssertEqual(doc.brushes.count, BrushLibrary.all.count)
    }

    // MARK: .inka round-trip

    func testWorkfileRoundTripStrokes() throws {
        var doc = InkaDocument.blank(width: 256, height: 128)
        doc.layers[0].content = .strokes([sampleStroke()])
        doc.palette = ["#010101", "#ff0000"]
        let data = try InkaWorkfile.encode(doc)
        let decoded = try InkaWorkfile.decode(data)
        XCTAssertEqual(decoded, doc)
    }

    func testWorkfileRoundTripRasterLayer() throws {
        // A tiny valid PNG (1×1) carried as a raster layer.
        let png = try XCTUnwrap(onePixelPNG())
        var doc = InkaDocument.blank(width: 8, height: 8)
        doc.layers.append(Layer(name: "Photo", content: .imported(png)))
        let decoded = try InkaWorkfile.decode(try InkaWorkfile.encode(doc))
        XCTAssertEqual(decoded.layers.count, 2)
        if case .imported(let back) = decoded.layers[1].content {
            XCTAssertEqual(back, png)
        } else {
            XCTFail("imported layer did not round-trip")
        }
    }

    func testDecodeReaddsMissingBuiltinBrushes() throws {
        var doc = InkaDocument.blank(width: 8, height: 8)
        doc.brushes = []  // an old/hand-edited file with no brush table
        let decoded = try InkaWorkfile.decode(try InkaWorkfile.encode(doc))
        XCTAssertEqual(decoded.brushes.count, BrushLibrary.all.count)
    }

    // MARK: Non-destructive rasterization

    func testFlattenPaintsStrokeLayer() throws {
        var doc = InkaDocument.blank(width: 256, height: 128)
        doc.layers[0].content = .strokes([sampleStroke()])
        let image = try XCTUnwrap(InkaRasterizer.flatten(doc))
        XCTAssertEqual(image.width, 256)
        XCTAssertGreaterThan(alpha(of: image, x: 110, y: 60), 0.5, "the stroke painted the middle")
        XCTAssertEqual(alpha(of: image, x: 2, y: 2), 0, accuracy: 0.02, "corner stays clear")
    }

    func testHiddenLayerIsNotRendered() throws {
        var doc = InkaDocument.blank(width: 256, height: 128)
        doc.layers[0].content = .strokes([sampleStroke()])
        doc.layers[0].isVisible = false
        let image = try XCTUnwrap(InkaRasterizer.flatten(doc))
        XCTAssertEqual(alpha(of: image, x: 110, y: 60), 0, accuracy: 0.02)
    }

    /// Changing the referenced brush changes the render — proves it is
    /// re-generated from the stored strokes, not baked.
    func testChangingTheBrushRerendersTheStroke() throws {
        var doc = InkaDocument.blank(width: 256, height: 128)
        doc.layers[0].content = .strokes([sampleStroke()])
        let thin = try XCTUnwrap(InkaRasterizer.flatten(doc))
        // Swap the ink pen for a fat airbrush under the same id.
        var fat = BrushLibrary.airbrush
        fat.id = BrushLibrary.inkPen.id
        doc.brushes = [fat]
        let wide = try XCTUnwrap(InkaRasterizer.flatten(doc))
        // The airbrush is far wider, so a point above the thin stroke is now painted.
        XCTAssertEqual(alpha(of: thin, x: 110, y: 30), 0, accuracy: 0.05)
        XCTAssertGreaterThan(alpha(of: wide, x: 110, y: 45), 0.05)
    }

    func testEraseStrokeRemovesPaintBeneathIt() throws {
        var doc = InkaDocument.blank(width: 256, height: 128)
        let paint = sampleStroke()  // a line across the middle (x 20…200, y 60)
        let eraseInput = StrokeInput(samples: [
            StrokeSample(position: CGPoint(x: 120, y: 60), pressure: 1),
            StrokeSample(position: CGPoint(x: 240, y: 60), pressure: 1),
        ])
        let erase = BrushStroke(
            brushID: BrushLibrary.inkPen.id, color: RGBA(r: 0, g: 0, b: 0),
            input: eraseInput, erase: true)
        doc.layers[0].content = .strokes([paint, erase])
        let image = try XCTUnwrap(InkaRasterizer.flatten(doc))
        XCTAssertGreaterThan(alpha(of: image, x: 40, y: 60), 0.5, "left half stays painted")
        XCTAssertEqual(
            alpha(of: image, x: 175, y: 60), 0, accuracy: 0.05, "erased where the eraser passed")
    }

    // MARK: helpers

    private func alpha(of image: CGImage, x: Int, y: Int) -> Double {
        guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
            return 0
        }
        return Double(ptr[y * image.bytesPerRow + x * 4 + 3]) / 255
    }

    private func onePixelPNG() -> PNGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let ctx = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let cg = ctx.makeImage(), let data = pngData(cg) else { return nil }
        return PNGImage(data: data, width: 1, height: 1)
    }

    private func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                out, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
