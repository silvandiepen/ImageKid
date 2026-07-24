import CoreGraphics
import XCTest

@testable import BrushKit

final class CodecAndRenderTests: XCTestCase {

    // MARK: .inkbrush round-trip

    func testInkBrushRoundTrip() throws {
        for original in BrushLibrary.all {
            let data = try InkBrushCoding.encode(original)
            let decoded = try InkBrushCoding.decode(data)
            XCTAssertEqual(decoded, original, "\(original.name) did not survive encode/decode")
        }
    }

    func testInkBrushIsVersioned() throws {
        let data = try InkBrushCoding.encode(BrushLibrary.pencil)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"version\""), "the format carries a version stamp")
    }

    // MARK: BrushStroke round-trip (the persisted hybrid stroke)

    func testBrushStrokeRoundTrip() throws {
        let input = StrokeInput(samples: [
            StrokeSample(position: CGPoint(x: 1, y: 2), pressure: 0.5, timestamp: 0),
            StrokeSample(position: CGPoint(x: 10, y: 12), pressure: 0.9, timestamp: 0.1),
        ])
        let stroke = BrushStroke(
            brushID: BrushLibrary.inkPen.id, color: RGBA(r: 1, g: 0, b: 0), input: input, seed: 99)
        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(BrushStroke.self, from: data)
        XCTAssertEqual(decoded, stroke)
        // And it re-generates the same dabs it would have live.
        let a = stroke.dabs(using: BrushLibrary.inkPen)
        let b = decoded.dabs(using: BrushLibrary.inkPen)
        XCTAssertEqual(a, b)
    }

    // MARK: Reference renderer

    func testRendererProducesOpaquePaintWhereTheStrokeIs() throws {
        // A short thick horizontal stroke across a transparent canvas.
        let input = StrokeInput(samples: [
            StrokeSample(position: CGPoint(x: 10, y: 32)),
            StrokeSample(position: CGPoint(x: 118, y: 32)),
        ])
        var brush = Brush(name: "Solid", tip: Brush.Tip(hardness: 1, spacing: 0.05), size: 24)
        brush.smoothing = 0
        brush.dynamics = Brush.Dynamics(pressureToSize: 0, pressureToOpacity: 0)
        let image = try XCTUnwrap(
            ReferenceRenderer.render(
                stroke: input, brush: brush, color: RGBA(r: 0, g: 0, b: 0),
                size: CGSize(width: 128, height: 64)))
        // Centre of the stroke is painted; a far corner stays transparent.
        XCTAssertGreaterThan(alpha(of: image, x: 64, y: 32), 0.9)
        XCTAssertEqual(alpha(of: image, x: 2, y: 2), 0, accuracy: 0.02)
    }

    /// The renderer is TOP-LEFT origin (matching BrushRender's Metal shader and
    /// the document): a dab near the top paints near the top, not mirrored to
    /// the bottom. An asymmetric probe — symmetric strokes hid this once.
    func testRendererIsTopLeftOrigin() throws {
        let dab = Dab(
            position: CGPoint(x: 32, y: 12), diameter: 16, angle: 0, roundness: 1,
            alpha: 1, hardness: 1, color: RGBA(r: 0, g: 0, b: 0))
        let image = try XCTUnwrap(
            ReferenceRenderer.render(dabs: [dab], size: CGSize(width: 64, height: 64)))
        XCTAssertGreaterThan(alpha(of: image, x: 32, y: 12), 0.9, "painted near the top")
        XCTAssertEqual(alpha(of: image, x: 32, y: 52), 0, accuracy: 0.02, "not mirrored to the bottom")
    }

    /// Straight-alpha at a pixel of a premultiplied-last RGBA8 CGImage.
    private func alpha(of image: CGImage, x: Int, y: Int) -> Double {
        guard let data = image.dataProvider?.data,
            let ptr = CFDataGetBytePtr(data)
        else { return 0 }
        let bpr = image.bytesPerRow
        return Double(ptr[y * bpr + x * 4 + 3]) / 255
    }
}
