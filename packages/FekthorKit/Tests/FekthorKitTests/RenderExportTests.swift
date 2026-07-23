import CoreGraphics
import ImageIO
import XCTest

@testable import FekthorKit

final class RenderExportTests: XCTestCase {
    // MARK: - Fixtures

    /// 10×10 document with a red 6×6 rect at (2,2).
    private func redRectDoc() -> GraphicDocument {
        var style = Style()
        style.fill = .color(r: 255, g: 0, b: 0)
        let rect = ShapeNode(
            id: 0, kind: .rect(x: 2, y: 2, width: 6, height: 6, rx: nil, ry: nil), style: style)
        return GraphicDocument(viewBox: ViewBox(width: 10, height: 10), nodes: [.shape(rect)])
    }

    // MARK: - Pixel helpers

    /// RGBA8 pixels (premultiplied, sRGB), row 0 = top scanline.
    private func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width
        let h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    private func px(_ data: [UInt8], width: Int, _ x: Int, _ y: Int)
        -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
    {
        let o = (y * width + x) * 4
        return (data[o], data[o + 1], data[o + 2], data[o + 3])
    }

    private func decodePNG(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: - Renderer

    func testRedRectOnTransparentBackground() throws {
        let image = try XCTUnwrap(GraphicRenderer.render(redRectDoc(), scale: 10))
        XCTAssertEqual(image.width, 100)
        XCTAssertEqual(image.height, 100)
        let data = rgba(image)
        // Centre is solid red, outside the rect fully transparent.
        let c = px(data, width: 100, 50, 50)
        XCTAssertEqual(c.r, 255)
        XCTAssertEqual(c.g, 0)
        XCTAssertEqual(c.b, 0)
        XCTAssertEqual(c.a, 255)
        XCTAssertEqual(px(data, width: 100, 5, 5).a, 0)
        XCTAssertEqual(px(data, width: 100, 95, 95).a, 0)
        // Red coverage ~ 60×60 px (antialiasing wiggles the edge rows).
        var red = 0
        for y in 0..<100 {
            for x in 0..<100 {
                let p = px(data, width: 100, x, y)
                if p.r > 200 && p.g < 50 && p.b < 50 && p.a > 200 { red += 1 }
            }
        }
        XCTAssertGreaterThan(red, 3400)
        XCTAssertLessThan(red, 3800)
    }

    func testDefaultBlackFillWhenNoFillDeclared() throws {
        let rect = ShapeNode(id: 0, kind: .rect(x: 0, y: 0, width: 10, height: 10, rx: nil, ry: nil))
        let doc = GraphicDocument(viewBox: ViewBox(width: 10, height: 10), nodes: [.shape(rect)])
        let data = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        let p = px(data, width: 100, 50, 50)
        XCTAssertEqual(p.r, 0)
        XCTAssertEqual(p.g, 0)
        XCTAssertEqual(p.b, 0)
        XCTAssertEqual(p.a, 255)
    }

    func testEvenOddFillRulePunchesHole() throws {
        func ringRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> RefinedPath {
            RefinedPath(
                start: Pt(x, y),
                segments: [
                    .line(to: Pt(x + w, y)), .line(to: Pt(x + w, y + h)),
                    .line(to: Pt(x, y + h)), .line(to: Pt(x, y)),
                ], closed: true)
        }
        var style = Style()
        style.fill = .color(r: 255, g: 0, b: 0)
        style.set("fill-rule", .keyword("evenodd"))
        let shape = ShapeNode(
            id: 0, kind: .path([ringRect(0, 0, 10, 10), ringRect(3, 3, 4, 4)]), style: style)
        let doc = GraphicDocument(viewBox: ViewBox(width: 10, height: 10), nodes: [.shape(shape)])
        let data = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        XCTAssertEqual(px(data, width: 100, 50, 50).a, 0)  // hole
        XCTAssertEqual(px(data, width: 100, 15, 50).r, 255)  // ring
        // Same geometry under nonzero winding fills solid.
        var solid = style
        solid.remove("fill-rule")
        var filledShape = shape
        filledShape.style = solid
        let doc2 = GraphicDocument(
            viewBox: ViewBox(width: 10, height: 10), nodes: [.shape(filledShape)])
        let data2 = rgba(try XCTUnwrap(GraphicRenderer.render(doc2, scale: 10)))
        XCTAssertEqual(px(data2, width: 100, 50, 50).r, 255)
    }

    func testGroupTransformAndOpacityCompose() throws {
        var style = Style()
        style.fill = .color(r: 255, g: 0, b: 0)
        let rect = ShapeNode(
            id: 0, kind: .rect(x: 0, y: 0, width: 5, height: 10, rx: nil, ry: nil), style: style)
        var groupStyle = Style()
        groupStyle.opacity = 0.5
        let group = GroupNode(
            id: 1, style: groupStyle,
            transform: TransformValue(raw: "translate(5 0)", matrix: [1, 0, 0, 1, 5, 0]),
            children: [.shape(rect)])
        let doc = GraphicDocument(viewBox: ViewBox(width: 10, height: 10), nodes: [.group(group)])
        let data = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        // Left half (untransformed position) is empty; right half is 50% red.
        XCTAssertEqual(px(data, width: 100, 25, 50).a, 0)
        let p = px(data, width: 100, 75, 50)
        XCTAssertEqual(Int(p.a), 128, accuracy: 3)
        XCTAssertEqual(Int(p.r), 128, accuracy: 3)  // premultiplied
    }

    func testLinearGradientFill() throws {
        var style = Style()
        style.fill = .linear(
            LinearGradient(
                p0: Pt(0, 5), p1: Pt(10, 5),
                stops: [
                    GradientStop(color: (r: 255, g: 0, b: 0), offset: 0),
                    GradientStop(color: (r: 0, g: 0, b: 255), offset: 1),
                ]))
        let rect = ShapeNode(
            id: 0, kind: .rect(x: 0, y: 0, width: 10, height: 10, rx: nil, ry: nil), style: style)
        let doc = GraphicDocument(viewBox: ViewBox(width: 10, height: 10), nodes: [.shape(rect)])
        let data = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        let left = px(data, width: 100, 5, 50)
        let right = px(data, width: 100, 95, 50)
        XCTAssertGreaterThan(left.r, left.b)  // red end
        XCTAssertGreaterThan(right.b, right.r)  // blue end
        XCTAssertEqual(left.a, 255)
        XCTAssertEqual(right.a, 255)
    }

    func testRadialGradientFill() throws {
        var style = Style()
        style.fill = .radial(
            RadialGradient(
                center: Pt(5, 5), radius: 5,
                stops: [
                    GradientStop(color: (r: 255, g: 255, b: 255), offset: 0),
                    GradientStop(color: (r: 0, g: 0, b: 0), offset: 1),
                ]))
        let rect = ShapeNode(
            id: 0, kind: .rect(x: 0, y: 0, width: 10, height: 10, rx: nil, ry: nil), style: style)
        let doc = GraphicDocument(viewBox: ViewBox(width: 10, height: 10), nodes: [.shape(rect)])
        let data = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        XCTAssertGreaterThan(px(data, width: 100, 50, 50).r, 200)  // white centre
        XCTAssertLessThan(px(data, width: 100, 2, 50).r, 80)  // dark rim
    }

    func testStrokeWidthAndDash() throws {
        var style = Style()
        style.stroke = .color(r: 0, g: 0, b: 0)
        style.strokeWidth = 2
        style.set("stroke-dasharray", .raw("2 2"))
        let line = ShapeNode(id: 0, kind: .line(Pt(0, 5), Pt(10, 5)), style: style)
        let doc = GraphicDocument(viewBox: ViewBox(width: 10, height: 10), nodes: [.shape(line)])
        let data = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        // Dash on-runs [0,2) and [4,6): x=1 painted, x=3 (gap) empty. A line
        // has no fill (SVG default fill cannot apply to <line>).
        XCTAssertEqual(px(data, width: 100, 10, 50).a, 255)
        XCTAssertEqual(px(data, width: 100, 30, 50).a, 0)
        XCTAssertEqual(px(data, width: 100, 10, 50).r, 0)
        // Stroke width 2 → nothing 3 units above the centreline.
        XCTAssertEqual(px(data, width: 100, 10, 20).a, 0)
    }

    // MARK: - Presentation attributes & display:none

    func testPresentationAttributeStylingRendersInExport() throws {
        // Styled ONLY by presentation attributes (the trace exporter's
        // shape): fill=/stroke=/stroke-width= live in attributes.extras, so
        // rendering from bare `effectiveStyle` would paint default black and
        // no stroke. `renderStyle` folds them in beneath the cascade.
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">\
            <rect width="10" height="10" fill="#00ff00"/>\
            <line x1="0" y1="5" x2="10" y2="5" fill="none" stroke="#ff0000" stroke-width="2"/>\
            </svg>
            """
        let doc = try SVGReader.read(svg)
        let data = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        let corner = px(data, width: 100, 5, 5)  // rect only: green, not black
        XCTAssertEqual(corner.r, 0)
        XCTAssertEqual(corner.g, 255)
        XCTAssertEqual(corner.a, 255)
        let mid = px(data, width: 100, 50, 50)  // on the stroked line: red
        XCTAssertEqual(mid.r, 255)
        XCTAssertEqual(mid.g, 0)
        // Stroke width 2 → nothing 3 units above the centreline (still rect green).
        XCTAssertEqual(px(data, width: 100, 50, 20).g, 255)
    }

    func testInlineStyleBeatsPresentationAttribute() throws {
        // SVG cascade: presentation attributes are the LOWEST layer.
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">\
            <rect width="10" height="10" fill="#00ff00" style="fill: #0000ff;"/>\
            </svg>
            """
        let doc = try SVGReader.read(svg)
        let data = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        let p = px(data, width: 100, 50, 50)
        XCTAssertEqual(p.b, 255)
        XCTAssertEqual(p.g, 0)
    }

    func testDisplayNoneLeavesNoPixels() throws {
        // Hidden shape (attribute form) and hidden group (whole subtree,
        // inline-style form) must not print in exports.
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">\
            <rect width="10" height="10" display="none"/>\
            <g style="display: none;"><circle cx="5" cy="5" r="4" fill="#ff0000"/></g>\
            </svg>
            """
        let doc = try SVGReader.read(svg)
        let data = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        for i in stride(from: 3, to: data.count, by: 4) {
            if data[i] != 0 { return XCTFail("pixel painted by a display:none node") }
        }
    }

    func testPDFHonoursPresentationAttributesAndDisplayNone() throws {
        // The PDF path shares GraphicRenderer.draw, so one sanity check:
        // attribute-styled rect renders green, hidden circle stays out.
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">\
            <rect width="10" height="10" fill="#00ff00"/>\
            <circle cx="5" cy="5" r="4" fill="#ff0000" display="none"/>\
            </svg>
            """
        let doc = try SVGReader.read(svg)
        let pdf = try XCTUnwrap(RasterExport.pdfData(doc))
        let data = try rasterizePDF(pdf, width: 100, height: 100)
        let centre = px(data, width: 100, 50, 50)
        XCTAssertEqual(centre.r, 0)  // hidden circle did not print
        XCTAssertEqual(centre.g, 255)  // presentation-attribute fill applied
    }

    // MARK: - PNG export

    func testPNGRoundTripMatchesDirectRender() throws {
        let doc = redRectDoc()
        let png = try XCTUnwrap(RasterExport.pngData(doc, scale: 10))
        let decoded = try XCTUnwrap(decodePNG(png))
        let direct = try XCTUnwrap(GraphicRenderer.render(doc, scale: 10))
        XCTAssertEqual(decoded.width, 100)
        XCTAssertEqual(decoded.height, 100)
        XCTAssertEqual(rgba(decoded), rgba(direct))
    }

    func testPNGFitContainLetterboxes() throws {
        let png = try XCTUnwrap(RasterExport.pngData(redRectDoc(), width: 40, height: 20))
        let decoded = try XCTUnwrap(decodePNG(png))
        XCTAssertEqual(decoded.width, 40)
        XCTAssertEqual(decoded.height, 20)
        let data = rgba(decoded)
        // 10×10 viewBox in 40×20 → content is the centre 20×20 (x 10..30);
        // the letterbox bands stay transparent, the rect centre renders red.
        XCTAssertEqual(px(data, width: 40, 5, 10).a, 0)
        XCTAssertEqual(px(data, width: 40, 35, 10).a, 0)
        let centre = px(data, width: 40, 20, 10)
        XCTAssertEqual(centre.r, 255)
        XCTAssertEqual(centre.a, 255)
    }

    func testPNGBackgroundColor() throws {
        let png = try XCTUnwrap(
            RasterExport.pngData(redRectDoc(), scale: 10, background: (r: 0, g: 255, b: 0)))
        let data = rgba(try XCTUnwrap(decodePNG(png)))
        let corner = px(data, width: 100, 5, 5)
        XCTAssertEqual(corner.g, 255)
        XCTAssertEqual(corner.a, 255)
        XCTAssertEqual(px(data, width: 100, 50, 50).r, 255)  // rect still on top
    }

    // MARK: - PDF export

    private func rasterizePDF(_ pdf: Data, width: Int, height: Int) throws -> [UInt8] {
        let provider = try XCTUnwrap(CGDataProvider(data: pdf as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(
                data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
            ctx.drawPDFPage(page)
        }
        return data
    }

    func testPDFParsesAndMatchesDirectRender() throws {
        var circleStyle = Style()
        circleStyle.fill = .color(r: 0, g: 0, b: 255)
        var doc = redRectDoc()
        doc.nodes.append(
            .shape(ShapeNode(id: 1, kind: .circle(center: Pt(7, 3), r: 2), style: circleStyle)))
        let pdf = try XCTUnwrap(RasterExport.pdfData(doc))

        let provider = try XCTUnwrap(CGDataProvider(data: pdf as CFData))
        let parsed = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertEqual(parsed.numberOfPages, 1)
        let box = try XCTUnwrap(parsed.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box, CGRect(x: 0, y: 0, width: 10, height: 10))

        // Rasterizing the vector PDF reproduces the direct render (≥99% of
        // pixels; edges antialias slightly differently).
        let fromPDF = try rasterizePDF(pdf, width: 100, height: 100)
        let direct = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        var matching = 0
        for i in stride(from: 0, to: direct.count, by: 4) {
            let close = (0..<4).allSatisfy { c in
                abs(Int(fromPDF[i + c]) - Int(direct[i + c])) <= 8
            }
            if close { matching += 1 }
        }
        XCTAssertGreaterThanOrEqual(Double(matching) / Double(direct.count / 4), 0.99)
    }

    func testPDFIsVectorNotEmbeddedBitmap() throws {
        let pdf = try XCTUnwrap(RasterExport.pdfData(redRectDoc()))
        // A rasterized export would carry an image XObject (`/Subtype /Image`
        // stays uncompressed in object dictionaries); vector output has none.
        XCTAssertFalse(pdf.range(of: Data("/Image".utf8)) != nil)
    }

    func testPDFCustomPageSize() throws {
        let pdf = try XCTUnwrap(
            RasterExport.pdfData(redRectDoc(), size: CGSize(width: 200, height: 100)))
        let provider = try XCTUnwrap(CGDataProvider(data: pdf as CFData))
        let parsed = try XCTUnwrap(CGPDFDocument(provider))
        let box = try XCTUnwrap(parsed.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box, CGRect(x: 0, y: 0, width: 200, height: 100))
        // Contain fit: content occupies the centre 100×100; bands transparent.
        let data = try rasterizePDF(pdf, width: 200, height: 100)
        XCTAssertEqual(px(data, width: 200, 10, 50).a, 0)
        XCTAssertEqual(px(data, width: 200, 190, 50).a, 0)
        XCTAssertEqual(px(data, width: 200, 100, 50).r, 255)
    }

    // MARK: - Determinism

    func testRenderAndPNGAreDeterministic() throws {
        let doc = redRectDoc()
        let a = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        let b = rgba(try XCTUnwrap(GraphicRenderer.render(doc, scale: 10)))
        XCTAssertEqual(a, b)
        let png1 = try XCTUnwrap(RasterExport.pngData(doc, scale: 10))
        let png2 = try XCTUnwrap(RasterExport.pngData(doc, scale: 10))
        // Bytes may legally differ across OS versions; decoded pixels do not.
        XCTAssertEqual(
            rgba(try XCTUnwrap(decodePNG(png1))), rgba(try XCTUnwrap(decodePNG(png2))))
    }

    func testDegenerateDocumentReturnsNil() {
        let doc = GraphicDocument(viewBox: ViewBox(width: 0, height: 10))
        XCTAssertNil(GraphicRenderer.render(doc, scale: 1))
        XCTAssertNil(RasterExport.pngData(doc))
        XCTAssertNil(RasterExport.pdfData(doc))
    }
}
