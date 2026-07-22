import XCTest

@testable import FekthorKit

final class Model2BridgeTests: XCTestCase {
    func testBridgeMapsAllElementForms() {
        var doc = VectorDocument(width: 100, height: 80)
        let rp = RefinedPath(
            start: Pt(0, 0), segments: [.line(to: Pt(10, 0)), .line(to: Pt(10, 10))],
            closed: true)
        doc.elements = [
            .fill(FillShape(id: "f0", color: (10, 20, 30), geometry: .refined([rp]))),
            .fill(
                FillShape(
                    id: "f1",
                    paint: .radial(
                        RadialGradient(
                            center: Pt(5, 5), radius: 9,
                            stops: [
                                GradientStop(color: (0, 0, 0), offset: 0),
                                GradientStop(color: (255, 255, 255), offset: 1),
                            ])),
                    geometry: .circle(center: Pt(5, 5), radius: 9))),
            .fill(
                FillShape(
                    id: "f2", color: (1, 2, 3),
                    geometry: .rect(
                        center: Pt(50, 40), w: 20, h: 10, rotation: .pi / 2, cornerRadius: 3))),
            .fill(FillShape(id: "f3", color: (7, 7, 7), rings: [[Pt(0, 0), Pt(4, 0), Pt(4, 4)]])),
            .stroke(
                StrokePath(
                    id: "s0", color: (0, 0, 0), width: 4, closed: false,
                    points: [Pt(0, 0), Pt(10, 10)], cap: .round, refined: nil)),
        ]

        let g = Model2Bridge.graphicDocument(from: doc)
        XCTAssertEqual(g.viewBox.width, 100)
        XCTAssertEqual(g.viewBox.height, 80)
        XCTAssertEqual(g.nodes.count, 5)

        // Refined fill keeps its typed path and colour.
        guard case .shape(let n0) = g.nodes[0], case .path(let paths0) = n0.kind else {
            return XCTFail()
        }
        XCTAssertEqual(paths0, [rp])
        XCTAssertEqual(n0.style.fill, .color(r: 10, g: 20, b: 30))
        XCTAssertEqual(n0.attributes.svgID, "f0")

        // Gradient circle stays a circle with a radial fill.
        guard case .shape(let n1) = g.nodes[1], case .circle(let c, let r) = n1.kind else {
            return XCTFail()
        }
        XCTAssertEqual(c, Pt(5, 5))
        XCTAssertEqual(r, 9)
        if case .radial? = n1.style.fill {} else { XCTFail("radial fill lost") }

        // Rotated rect: primitive + rotation transform, corner radius kept.
        guard case .shape(let n2) = g.nodes[2], case .rect(_, _, let w, let h, let rx, _) = n2.kind
        else { return XCTFail() }
        XCTAssertEqual(w, 20)
        XCTAssertEqual(h, 10)
        XCTAssertEqual(rx, 3)
        XCTAssertNotNil(n2.transform)
        // The transform maps the rect centre onto itself.
        let centre = n2.transform!.apply(Pt(50, 40))
        XCTAssertEqual(centre.x, 50, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 40, accuracy: 1e-9)

        // Legacy rings become exact closed polygon paths.
        guard case .shape(let n3) = g.nodes[3], case .path(let paths3) = n3.kind else {
            return XCTFail()
        }
        XCTAssertTrue(paths3[0].closed)
        XCTAssertEqual(paths3[0].segments.count, 2)

        // Stroke: fill none + stroke colour/width/cap, open path.
        guard case .shape(let n4) = g.nodes[4], case .path(let paths4) = n4.kind else {
            return XCTFail()
        }
        XCTAssertEqual(n4.style.fill, PaintValue.none)
        XCTAssertEqual(n4.style.stroke, .color(r: 0, g: 0, b: 0))
        XCTAssertEqual(n4.style.strokeWidth, 4)
        XCTAssertEqual(n4.style.value(of: "stroke-linecap"), .keyword("round"))
        XCTAssertFalse(paths4[0].closed)

        // Deterministic: bridging twice yields equal documents.
        XCTAssertEqual(g, Model2Bridge.graphicDocument(from: doc))
    }
}
