import XCTest

@testable import FekthorKit

/// Named graphic styles: class-bound apply (inline values, class marker),
/// SVG round-trip, capture→apply→propagate cycle, changed-docs-only
/// propagation, and unapply.
final class NamedStyleTests: XCTestCase {
    let brand = NamedStyle(
        name: "brand-stroke",
        declarations: [
            "fill": "none", "stroke": "#ed2024", "stroke-width": "4",
            "stroke-linecap": "round", "stroke-linejoin": "miter",
        ])

    func makeNode(id: Int = 0, style: String, klass: String? = nil) -> ShapeNode {
        var attributes = NodeAttributes()
        if let klass { attributes.extras.append(XMLAttr(name: "class", value: klass)) }
        return ShapeNode(
            id: id, kind: .line(Pt(18, 36), Pt(54, 36)), style: SVGStyle.parse(style),
            attributes: attributes)
    }

    // MARK: Apply

    func testApplySetsClassAndInlineValues() {
        let node = makeNode(style: "fill: none; stroke: #010101;", klass: "decor old-style")
        let applied = NamedStyles.apply(brand, to: node, replacing: ["old-style"])
        // Old fekthor style class swapped out, foreign class preserved, in place.
        XCTAssertEqual(
            applied.attributes.extras.first(where: { $0.name == "class" })?.value,
            "decor brand-stroke")
        // Existing declarations update in place, new ones append canonically.
        XCTAssertEqual(
            SVGStyle.serialize(applied.style),
            "fill: none; stroke: #ed2024; stroke-width: 4; stroke-linecap: round; "
                + "stroke-linejoin: miter;")
        // Re-applying is a no-op (canonical order is stable).
        XCTAssertEqual(NamedStyles.apply(brand, to: applied), applied)
    }

    func testApplyAddsClassAttributeWhenAbsent() {
        let applied = NamedStyles.apply(brand, to: makeNode(style: "stroke: #010101;"))
        XCTAssertEqual(
            applied.attributes.extras.first(where: { $0.name == "class" })?.value,
            "brand-stroke")
    }

    func testApplyRoundTripsThroughSVG() throws {
        var doc = GraphicDocument.blank(width: 72, height: 72, id: "icon")
        doc.nodes = [
            .shape(NamedStyles.apply(brand, to: makeNode(style: "fill: none; stroke: #010101;")))
        ]
        let restored = try SVGReader.read(SVGWriter.write(doc))
        guard case .shape(let s) = restored.nodes[0] else { return XCTFail("shape expected") }
        // Class survives as the binding marker; values are inline.
        XCTAssertEqual(
            s.attributes.extras.first(where: { $0.name == "class" })?.value, "brand-stroke")
        XCTAssertEqual(s.style.stroke, .color(r: 0xed, g: 0x20, b: 0x24))
        XCTAssertEqual(s.style.strokeWidth, 4)
        XCTAssertEqual(s.style.value(of: "stroke-linecap"), .keyword("round"))
        XCTAssertEqual(NamedStyles.boundNodes(in: restored, styleName: "brand-stroke"), [s.id])
        // The document stays self-contained: idempotent second write.
        XCTAssertEqual(SVGWriter.write(restored), SVGWriter.write(try SVGReader.read(SVGWriter.write(restored))))
    }

    // MARK: Capture → apply → propagate

    func testCaptureApplyPropagateCycle() {
        let source = makeNode(
            style: "fill: none; stroke: #010101; stroke-width: 4px; stroke-linecap: round; "
                + "mix-blend-mode: multiply;")
        var captured = NamedStyles.capture(from: source, name: "outline")
        // Paint-related declarations only; foreign properties are not captured.
        XCTAssertEqual(
            captured.declarations,
            [
                "fill": "none", "stroke": "#010101", "stroke-width": "4px",
                "stroke-linecap": "round",
            ])

        var doc = GraphicDocument.blank(width: 72, height: 72)
        doc.nodes = [
            .shape(NamedStyles.apply(captured, to: makeNode(id: 0, style: "stroke: #010101;")))
        ]
        // Edit the style, propagate: the bound node follows.
        captured.declarations["stroke"] = "#ed2024"
        let changed = NamedStyles.propagate(captured, docs: ["a.svg": doc])
        XCTAssertEqual(Array(changed.keys), ["a.svg"])
        guard case .shape(let s) = changed["a.svg"]!.nodes[0] else {
            return XCTFail("shape expected")
        }
        XCTAssertEqual(s.style.stroke, .color(r: 0xed, g: 0x20, b: 0x24))
        XCTAssertEqual(s.style.strokeWidth, 4)
    }

    // MARK: Propagation save contract

    func testPropagateReturnsOnlyChangedDocs() {
        // bound + stale values → changes; bound + already current → no
        // change; unbound (foreign class) → no change.
        var stale = GraphicDocument.blank(width: 72, height: 72)
        stale.nodes = [
            .shape(
                makeNode(
                    id: 0, style: "opacity: .5; stroke: #010101;",
                    klass: "decor brand-stroke"))
        ]
        var current = GraphicDocument.blank(width: 72, height: 72)
        current.nodes = [
            .shape(NamedStyles.apply(brand, to: makeNode(id: 0, style: "")))
        ]
        var foreign = GraphicDocument.blank(width: 72, height: 72)
        foreign.nodes = [
            .shape(makeNode(id: 0, style: "stroke: #010101;", klass: "other-style"))
        ]
        let changed = NamedStyles.propagate(
            brand, docs: ["stale.svg": stale, "current.svg": current, "foreign.svg": foreign])
        XCTAssertEqual(Array(changed.keys), ["stale.svg"])
        guard case .shape(let s) = changed["stale.svg"]!.nodes[0] else {
            return XCTFail("shape expected")
        }
        // Foreign declaration keeps its value AND position; owned ones update
        // in place / append canonically. Class list untouched.
        XCTAssertEqual(
            SVGStyle.serialize(s.style),
            "opacity: .5; stroke: #ed2024; fill: none; stroke-width: 4; "
                + "stroke-linecap: round; stroke-linejoin: miter;")
        XCTAssertEqual(
            s.attributes.extras.first(where: { $0.name == "class" })?.value,
            "decor brand-stroke")
    }

    func testBoundNodesWalksGroups() {
        var doc = GraphicDocument.blank(width: 72, height: 72)
        doc.nodes = [
            .shape(makeNode(id: 0, style: "", klass: "brand-stroke")),
            .group(
                GroupNode(
                    id: 1,
                    attributes: NodeAttributes(extras: [
                        XMLAttr(name: "class", value: "brand-stroke")
                    ]),
                    children: [.shape(makeNode(id: 2, style: "", klass: "other"))])),
        ]
        XCTAssertEqual(NamedStyles.boundNodes(in: doc, styleName: "brand-stroke"), [0, 1])
    }

    // MARK: Unapply

    func testUnapplyDropsClassKeepsValues() {
        let applied = NamedStyles.apply(
            brand, to: makeNode(style: "stroke: #010101;", klass: "decor"))
        let released = NamedStyles.unapply(applied, styleName: "brand-stroke")
        XCTAssertEqual(
            released.attributes.extras.first(where: { $0.name == "class" })?.value, "decor")
        XCTAssertEqual(released.style, applied.style)  // inline values stay

        // Sole class → attribute removed entirely.
        let solo = NamedStyles.apply(brand, to: makeNode(style: ""))
        let bare = NamedStyles.unapply(solo, styleName: "brand-stroke")
        XCTAssertNil(bare.attributes.extras.first(where: { $0.name == "class" }))
    }
}
