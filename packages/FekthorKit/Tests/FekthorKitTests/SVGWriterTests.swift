import XCTest

@testable import FekthorKit

final class SVGWriterTests: XCTestCase {
    func idempotent(_ source: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let doc1 = try SVGReader.read(source)
        let s1 = SVGWriter.write(doc1)
        let doc2 = try SVGReader.read(s1)
        let s2 = SVGWriter.write(doc2)
        XCTAssertEqual(s1, s2, "write∘read not idempotent", file: file, line: line)
        XCTAssertEqual(doc2, try SVGReader.read(s2), "model drift", file: file, line: line)
    }

    func testIdempotenceOnCorpusShapes() throws {
        try idempotent(
            """
            <svg id="add-m" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 72"><line x1="36" y1="18" x2="36" y2="54" style="fill: none; stroke-miterlimit: 10; stroke-width: 4px;"/><line x1="18" y1="36" x2="54" y2="36" style="fill: none; stroke: #010101;"/></svg>
            """)
        try idempotent(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <svg id="elevator_4" data-name="elevator 4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 72">
              <g style="opacity: .5;" transform="translate(2 3)">
                <path d="M30.7,46.19v7.14c0,.55.45,1,1,1h4.3Z" style="fill: none; stroke: #ed2024; stroke-width: 4px;"/>
                <rect x="10" y="12" width="20" height="8" rx="2" style="fill: #010101;"/>
              </g>
              <circle cx="36" cy="36" r="5" style="fill: #ed2024; opacity: .5;"/>
              <polygon points="0,0 4,0 4,4" style="fill: #fff;"/>
            </svg>
            """)
        try idempotent(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 72">
              <defs><clipPath id="c0"><rect width="10" height="10"/></clipPath></defs>
              <style>.st0 { fill: none; stroke: #010101; }</style>
              <path class="st0" d="M0,0L10,10"/>
            </svg>
            """)
        // CSS-variable built flavour: raw values must survive untouched.
        try idempotent(
            """
            <svg id="x" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 72"><path d="M0,0L1,1" style="fill: var(--icon-fill, rgba(0, 0, 0, 0)); stroke-width:var(--icon-stroke-width-m, calc(var(--icon-stroke-width, 5) * 1));"/></svg>
            """)
    }

    func testDeterminism() throws {
        let doc = try SVGReader.read(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 72"><circle cx="36" cy="36" r="9" style="fill: #ed2024;"/></svg>
            """)
        XCTAssertEqual(SVGWriter.write(doc), SVGWriter.write(doc))
    }

    func testXMLDeclarationPreservedOnlyWhenPresent() throws {
        let with = try SVGReader.read(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"x\" viewBox=\"0 0 1 1\"/>")
        XCTAssertTrue(SVGWriter.write(with).hasPrefix("<?xml"))
        let without = try SVGReader.read("<svg xmlns=\"x\" viewBox=\"0 0 1 1\"/>")
        XCTAssertFalse(SVGWriter.write(without).hasPrefix("<?xml"))
    }

    func testArcsBecomeCubicsByDefault() throws {
        let doc = try SVGReader.read(
            "<svg xmlns=\"x\" viewBox=\"0 0 20 20\"><path d=\"M10 0 A10 10 0 0 1 0 10\"/></svg>")
        let out = SVGWriter.write(doc)
        XCTAssertFalse(out.contains("A"), "arcs should be cubics by default: \(out)")
        let arcs = SVGWriter.write(doc, options: .init(emitArcs: true))
        XCTAssertTrue(arcs.contains("A10,10"))
        // Geometry equivalence: every point of the cubic form lies on the
        // original circle (radius 10 about the origin) within a small
        // tolerance — pointwise zip is invalid across parameterizations.
        let round = try SVGReader.read(out)
        guard case .shape(let b) = round.nodes[0], case .path(let pb) = b.kind
        else { return XCTFail() }
        for p in pb.flatMap({ PathRefine.flatten($0) }) {
            let r = (p.x * p.x + p.y * p.y).squareRoot()
            XCTAssertEqual(r, 10, accuracy: 0.05)
        }
    }

    func testGradientFillGetsDefs() throws {
        var doc = GraphicDocument.blank(width: 20, height: 20)
        var style = Style()
        style.fill = .radial(
            RadialGradient(
                center: Pt(10, 10), radius: 8,
                stops: [
                    GradientStop(color: (0, 0, 0), offset: 0),
                    GradientStop(color: (255, 255, 255), offset: 1),
                ]))
        doc.nodes = [.shape(ShapeNode(id: 0, kind: .circle(center: Pt(10, 10), r: 8), style: style))]
        let out = SVGWriter.write(doc)
        XCTAssertTrue(out.contains("<defs>"))
        XCTAssertTrue(out.contains("radialGradient id=\"grad-0\""))
        XCTAssertTrue(out.contains("fill: url(#grad-0);"))
        // Idempotent through the reference form.
        let round = try SVGReader.read(out)
        let out2 = SVGWriter.write(round)
        XCTAssertEqual(SVGWriter.write(try SVGReader.read(out2)), out2)
    }
}
