import XCTest

@testable import FekthorKit

final class Model2Tests: XCTestCase {
    func testStyleOrderPreservationAndAccessors() {
        var style = Style(declarations: [
            StyleDeclaration(name: "fill", value: .paint(.none)),
            StyleDeclaration(name: "stroke", value: .paint(.color(r: 1, g: 1, b: 1))),
            StyleDeclaration(name: "stroke-miterlimit", value: .number(10, unit: nil)),
            StyleDeclaration(name: "stroke-width", value: .number(4, unit: "px")),
        ])
        XCTAssertEqual(style.strokeWidth, 4)
        // Updating in place keeps the position and the px unit.
        style.strokeWidth = 6
        XCTAssertEqual(style.declarations[3].name, "stroke-width")
        if case .number(let n, let u) = style.declarations[3].value {
            XCTAssertEqual(n, 6)
            XCTAssertEqual(u, "px")
        } else {
            XCTFail()
        }
        // New property appends at the end.
        style.set("opacity", .number(0.5, unit: nil))
        XCTAssertEqual(style.declarations.last?.name, "opacity")
        // fill/stroke coexist — the model v2 point.
        style.fill = .color(r: 237, g: 32, b: 36)
        XCTAssertNotNil(style.fill)
        XCTAssertNotNil(style.stroke)
    }

    func testHexParsing() {
        XCTAssertEqual(PaintValue.parseHex("#010101")?.r, 1)
        XCTAssertEqual(PaintValue.parseHex("#fff")?.b, 255)
        XCTAssertEqual(PaintValue.parseHex("#ED2024")?.g, 32)
        XCTAssertNil(PaintValue.parseHex("red"))
    }

    func testVarFallbackRenderColor() {
        let p = PaintValue.raw("var(--icon-stroke-color, #ed2024)")
        XCTAssertEqual(p.renderColor?.r, 237)
        XCTAssertEqual(PaintValue.raw("currentColor").renderColor?.r, 0)
    }

    func testDocumentEqualityAndIDs() {
        func make() -> GraphicDocument {
            var doc = GraphicDocument.blank(width: 72, height: 72, id: "test")
            doc.nodes = [
                .shape(
                    ShapeNode(
                        id: 0, kind: .line(Pt(18, 36), Pt(54, 36)),
                        style: Style(declarations: [
                            StyleDeclaration(name: "fill", value: .paint(.none))
                        ]))),
                .group(
                    GroupNode(
                        id: 1,
                        children: [
                            .shape(ShapeNode(id: 2, kind: .circle(center: Pt(36, 36), r: 10)))
                        ])),
            ]
            return doc
        }
        XCTAssertEqual(make(), make())  // deterministic ids → equal documents
        XCTAssertEqual(make().nextNodeID, 3)
        var doc = make()
        XCTAssertNotNil(doc.firstShape(id: 2))
        var inner = doc.firstShape(id: 2)!
        inner.style.fill = .color(r: 1, g: 1, b: 1)
        XCTAssertTrue(doc.replaceShape(id: 2, with: inner))
        XCTAssertNotNil(doc.firstShape(id: 2)?.style.fill)
        XCTAssertFalse(doc.replaceShape(id: 99, with: inner))
    }

    func testTransformApply() {
        let t = TransformValue(raw: "translate(10 5)", matrix: [1, 0, 0, 1, 10, 5])
        XCTAssertEqual(t.apply(Pt(1, 1)).x, 11)
        XCTAssertEqual(t.apply(Pt(1, 1)).y, 6)
    }
}
