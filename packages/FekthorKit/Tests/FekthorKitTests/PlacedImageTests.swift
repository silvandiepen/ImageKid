import CoreGraphics
import XCTest

@testable import FekthorKit

/// Placed rasters (`<image>`) and the Vectorize handoff: a pasted image stays
/// an image through save/reopen, and tracing it puts the vectors back exactly
/// where the picture was.
final class PlacedImageTests: XCTestCase {

    /// A tiny opaque test bitmap.
    private func bitmap(_ w: Int, _ h: Int) -> CGImage {
        let raster = RasterImage(
            width: w, height: h, data: [UInt8](repeating: 200, count: w * h * 4))
        return raster.cgImage()!
    }

    // MARK: Data URIs

    func testPNGDataURIRoundTrip() throws {
        let href = try XCTUnwrap(ImageEmbed.dataURI(for: bitmap(6, 4)))
        XCTAssertTrue(href.hasPrefix(ImageEmbed.pngPrefix))
        let decoded = try XCTUnwrap(ImageEmbed.decode(href))
        XCTAssertEqual(decoded.width, 6)
        XCTAssertEqual(decoded.height, 4)
        // External references are preserved but never fetched.
        XCTAssertNil(ImageEmbed.decode("https://example.com/logo.png"))
        XCTAssertNil(ImageEmbed.decode(""))
    }

    // MARK: SVG round-trip

    func testImageNodeSurvivesReadWriteRead() throws {
        let href = try XCTUnwrap(ImageEmbed.dataURI(for: bitmap(8, 8)))
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <image x="2" y="3" width="20" height="18" href="\(href)"/>
              <rect x="0" y="0" width="4" height="4"/>
            </svg>
            """
        let doc = try SVGReader.read(svg)
        guard case .image(let image) = doc.nodes.first else {
            return XCTFail("the <image> did not become an image node")
        }
        XCTAssertEqual(image.href, href)
        XCTAssertEqual(image.x, 2)
        XCTAssertEqual(image.y, 3)
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 18)
        // The writer is deterministic and idempotent over images too.
        let once = SVGWriter.write(doc)
        XCTAssertEqual(once, SVGWriter.write(doc))
        XCTAssertTrue(once.contains("<image"))
        let reread = try SVGReader.read(once)
        XCTAssertEqual(SVGWriter.write(reread), once)
        XCTAssertEqual(reread.nodes.count, 2)
    }

    /// `xlink:href` (legacy exports) reads, and normalizes to plain `href`.
    func testLegacyXlinkHrefIsNormalized() throws {
        let doc = try SVGReader.read(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
              <image xlink:href="data:image/png;base64,AAAA" width="10" height="10"/>
            </svg>
            """)
        guard case .image(let image) = doc.nodes.first else { return XCTFail("not an image") }
        XCTAssertEqual(image.href, "data:image/png;base64,AAAA")
        let text = SVGWriter.write(doc)
        XCTAssertTrue(text.contains(" href=\"data:image/png;base64,AAAA\""))
        XCTAssertFalse(text.contains("xlink:href"))
    }

    // MARK: Geometry

    func testTranslateAndScaleFoldIntoTheRect() {
        let image = ImageNode(id: 0, href: "x", x: 10, y: 20, width: 40, height: 30)
        let moved = image.translated(dx: 5, dy: -5)
        XCTAssertNil(moved.transform, "a pure move must not add a transform attribute")
        XCTAssertEqual(moved.x, 15)
        XCTAssertEqual(moved.y, 15)
        let scaled = image.scaled(sx: 2, sy: 2, around: Pt(10, 20))
        XCTAssertNil(scaled.transform)
        XCTAssertEqual(scaled.x, 10)
        XCTAssertEqual(scaled.y, 20)
        XCTAssertEqual(scaled.width, 80)
        XCTAssertEqual(scaled.height, 60)
    }

    func testRotationUsesATransformAndKeepsBounds() {
        let image = ImageNode(id: 0, href: "x", x: 0, y: 0, width: 10, height: 20)
        let turned = image.rotated(by: .pi / 2, around: Pt(0, 0))
        let transform = turned.transform
        XCTAssertNotNil(transform)
        XCTAssertFalse(transform?.raw.isEmpty ?? true, "an empty raw would be dropped on write")
        // A quarter turn about the origin swaps the extents.
        let b = turned.bounds
        XCTAssertEqual(b.maxX - b.minX, 20, accuracy: 1e-9)
        XCTAssertEqual(b.maxY - b.minY, 10, accuracy: 1e-9)
    }

    // MARK: Vectorize placement

    func testTracedNodesLandInsideTheImageFrame() {
        // A traced document on a 100×100 pixel grid: one 4pt-stroked path
        // spanning the whole grid.
        var style = Style()
        style.set("fill", .paint(.none))
        style.set("stroke", .paint(.color(r: 0, g: 0, b: 0)))
        style.set("stroke-width", .number(4, unit: nil))
        let path = RefinedPath(
            start: Pt(0, 0), segments: [.line(to: Pt(100, 100))], closed: false)
        let traced = GraphicDocument(
            viewBox: ViewBox(width: 100, height: 100),
            nodes: [.shape(ShapeNode(id: 0, kind: .path([path]), style: style))])

        let placed = TracePlacement.nodes(
            of: traced, into: (x: 10, y: 20, width: 50, height: 50), firstID: 7)
        XCTAssertEqual(placed.count, 1)
        guard case .shape(let shape) = placed[0] else { return XCTFail("expected a shape") }
        XCTAssertEqual(shape.id, 7, "ids continue from the target document")
        let bounds = try? XCTUnwrap(Editing2.bounds(of: shape))
        XCTAssertEqual(bounds?.minX ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(bounds?.minY ?? 0, 20, accuracy: 1e-9)
        XCTAssertEqual(bounds?.maxX ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(bounds?.maxY ?? 0, 70, accuracy: 1e-9)
        // Stroke width follows the placement (half size → half width).
        XCTAssertEqual(shape.style.strokeWidth ?? 0, 2, accuracy: 1e-9)
    }

    func testGradientCoordinatesFollowThePlacement() {
        var style = Style()
        style.set(
            "fill",
            .paint(
                .linear(
                    LinearGradient(
                        p0: Pt(0, 0), p1: Pt(100, 0),
                        stops: [
                            GradientStop(color: (0, 0, 0), offset: 0),
                            GradientStop(color: (255, 255, 255), offset: 1),
                        ]))))
        let traced = GraphicDocument(
            viewBox: ViewBox(width: 100, height: 100),
            nodes: [
                .shape(
                    ShapeNode(
                        id: 0, kind: .rect(x: 0, y: 0, width: 100, height: 100, rx: nil, ry: nil),
                        style: style))
            ])
        let placed = TracePlacement.nodes(
            of: traced, into: (x: 10, y: 10, width: 50, height: 50), firstID: 0)
        guard case .shape(let shape) = placed.first,
            case .linear(let gradient)? = shape.style.fill
        else { return XCTFail("expected a gradient fill") }
        XCTAssertEqual(gradient.p0.x, 10, accuracy: 1e-9)
        XCTAssertEqual(gradient.p1.x, 60, accuracy: 1e-9)
    }

    // MARK: Rendering

    /// The renderer draws a placed image the right way up and in the right
    /// place — a flipped context is the classic way to get this wrong.
    func testRendererDrawsTheImageUprightInsideItsRect() throws {
        // 8×8: red top half, blue bottom half (top-left origin).
        var pixels = [UInt8]()
        for y in 0..<8 {
            for _ in 0..<8 {
                pixels.append(contentsOf: y < 4 ? [255, 0, 0, 255] : [0, 0, 255, 255])
            }
        }
        let source = RasterImage(width: 8, height: 8, data: pixels)
        let href = try XCTUnwrap(ImageEmbed.dataURI(for: source))
        let doc = GraphicDocument(
            viewBox: ViewBox(width: 20, height: 20),
            nodes: [.image(ImageNode(id: 0, href: href, x: 4, y: 4, width: 8, height: 8))])

        let rendered = try XCTUnwrap(GraphicRenderer.render(doc, scale: 1))
        let out = try RasterImage.from(cgImage: rendered)
        XCTAssertEqual(out.width, 20)
        // Inside the rect: red on top, blue below — not the other way round.
        XCTAssertEqual(out.pixel(8, 5).0, 255, "the image's top half should be red")
        XCTAssertEqual(out.pixel(8, 5).2, 0)
        XCTAssertEqual(out.pixel(8, 10).2, 255, "the image's bottom half should be blue")
        XCTAssertEqual(out.pixel(8, 10).0, 0)
        // Outside the rect nothing was drawn.
        XCTAssertEqual(out.pixel(1, 1).3, 0, "the area outside the image must stay transparent")
    }

    func testReplaceNodeSwapsInPlaceKeepingZOrder() {
        let image = ImageNode(id: 1, href: "x", x: 0, y: 0, width: 10, height: 10)
        var doc = GraphicDocument(
            viewBox: ViewBox(width: 10, height: 10),
            nodes: [
                .shape(ShapeNode(id: 0, kind: .circle(center: Pt(1, 1), r: 1))),
                .image(image),
                .shape(ShapeNode(id: 2, kind: .circle(center: Pt(9, 9), r: 1))),
            ])
        XCTAssertNotNil(doc.firstImage(id: 1))
        let replaced = doc.replaceNode(
            id: 1,
            with: [
                .shape(ShapeNode(id: 3, kind: .circle(center: Pt(5, 5), r: 2))),
                .shape(ShapeNode(id: 4, kind: .circle(center: Pt(6, 6), r: 2))),
            ])
        XCTAssertTrue(replaced)
        XCTAssertEqual(doc.nodes.map(\.id), [0, 3, 4, 2])
        XCTAssertNil(doc.firstImage(id: 1), "the image is gone once vectorized")
    }
}
