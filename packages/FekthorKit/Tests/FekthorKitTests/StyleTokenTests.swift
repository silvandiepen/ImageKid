import XCTest

@testable import FekthorKit

/// P3 style-token engine: colour normalization, colour-slot binding scan,
/// workspace propagation (only changed docs returned, untouched declarations
/// verbatim), draw-with-style, and a realism pass over real open-icon
/// fixtures (two-slot corpus: outline #010101, accent #ed2024).
final class StyleTokenTests: XCTestCase {
    let tokens: [Workfile.StyleToken] = [
        .init(name: "outline", value: "#010101"),
        .init(name: "accent", value: "#ed2024"),
    ]

    // MARK: Normalization

    func testNormalizeColor() {
        XCTAssertEqual(StyleTokens.normalizeColor("#010101"), .init(r: 1, g: 1, b: 1))
        XCTAssertEqual(StyleTokens.normalizeColor("#eee"), .init(r: 238, g: 238, b: 238))
        XCTAssertEqual(StyleTokens.normalizeColor("#ED2024"), .init(r: 237, g: 32, b: 36))
        XCTAssertEqual(StyleTokens.normalizeColor("rgb(1,1,1)"), .init(r: 1, g: 1, b: 1))
        XCTAssertEqual(
            StyleTokens.normalizeColor("rgb(237, 32, 36)"), .init(r: 237, g: 32, b: 36))
        XCTAssertEqual(StyleTokens.normalizeColor("  #010101  "), .init(r: 1, g: 1, b: 1))
        XCTAssertNil(StyleTokens.normalizeColor("none"))
        XCTAssertNil(StyleTokens.normalizeColor("#0101"))
        XCTAssertNil(StyleTokens.normalizeColor("rgb(256, 0, 0)"))
        XCTAssertNil(StyleTokens.normalizeColor("rgb(1, 1)"))
        XCTAssertNil(StyleTokens.normalizeColor("url(#grad-0)"))
        XCTAssertNil(StyleTokens.normalizeColor("var(--outline, #010101)"))
    }

    func testHexTextMatchesCorpusFormatting() {
        XCTAssertEqual(StyleTokens.RGB(r: 1, g: 1, b: 1).hexText, "#010101")
        XCTAssertEqual(StyleTokens.RGB(r: 0x22, g: 0x22, b: 0x22).hexText, "#222")
        XCTAssertEqual(StyleTokens.RGB(r: 237, g: 32, b: 36).hexText, "#ed2024")
    }

    // MARK: Binding scan

    /// Synthetic doc: outline-stroked line at root, a group holding an
    /// accent fill plus a decoy near-miss (#010102) shape whose stroke is
    /// rgb(1,1,1), and a shape carrying a non-paint colour declaration
    /// (stop-color) plus an unbound #eee fill.
    func makeDoc() -> GraphicDocument {
        var doc = GraphicDocument.blank(width: 72, height: 72, id: "synthetic")
        doc.nodes = [
            .shape(
                ShapeNode(
                    id: 0, kind: .line(Pt(18, 36), Pt(54, 36)),
                    style: SVGStyle.parse("fill: none; stroke: #010101; stroke-width: 4px;"))),
            .group(
                GroupNode(
                    id: 1, style: SVGStyle.parse("opacity: .5;"),
                    children: [
                        .shape(
                            ShapeNode(
                                id: 2,
                                kind: .rect(x: 9, y: 9, width: 18, height: 18, rx: nil, ry: nil),
                                style: SVGStyle.parse("fill: #ed2024; stroke-width: 0px;"))),
                        .shape(
                            ShapeNode(
                                id: 3, kind: .circle(center: Pt(36, 36), r: 6),
                                style: SVGStyle.parse("fill: #010102; stroke: rgb(1,1,1);"))),
                    ])),
            .shape(
                ShapeNode(
                    id: 4, kind: .ellipse(center: Pt(36, 54), rx: 9, ry: 6),
                    style: SVGStyle.parse("stop-color: #010101; fill: #eee;"))),
        ]
        return doc
    }

    func testBindingScan() {
        let doc = makeDoc()
        let found = StyleTokens.bindings(in: doc, tokens: tokens)
        XCTAssertEqual(
            found,
            [
                .init(nodeID: 0, property: "stroke", token: "outline"),
                .init(nodeID: 2, property: "fill", token: "accent"),
                .init(nodeID: 3, property: "stroke", token: "outline"),  // rgb(1,1,1)
                .init(nodeID: 4, property: "stop-color", token: "outline"),
            ])
        // The near-miss decoy must NOT bind.
        XCTAssertFalse(found.contains { $0.nodeID == 3 && $0.property == "fill" })
        // Deterministic: a second scan is identical.
        XCTAssertEqual(found, StyleTokens.bindings(in: doc, tokens: tokens))
    }

    func testUnboundColors() {
        let unbound = StyleTokens.unboundColors(in: makeDoc(), tokens: tokens)
        XCTAssertEqual(
            unbound,
            [
                .init(r: 1, g: 1, b: 2),  // decoy, document order first
                .init(r: 238, g: 238, b: 238),
            ])
        XCTAssertEqual(unbound.map(\.hexText), ["#010102", "#eee"])
    }

    // MARK: Propagation

    func testPropagationRewritesOnlyBoundPaintsAndOnlyChangedDocs() throws {
        let docA = makeDoc()
        // docB carries only the accent slot — changing outline must not
        // return it.
        var docB = GraphicDocument.blank(width: 72, height: 72)
        docB.nodes = [
            .shape(
                ShapeNode(
                    id: 0, kind: .circle(center: Pt(36, 36), r: 18),
                    style: SVGStyle.parse("fill: #ed2024; stroke-width: 0px;")))
        ]

        let changed = StyleTokens.apply(
            tokens: tokens, changing: "outline", to: "#222222",
            docs: ["a.svg": docA, "b.svg": docB])
        XCTAssertEqual(Array(changed.keys), ["a.svg"])

        let rewritten = try XCTUnwrap(changed["a.svg"])
        let before = SVGWriter.write(docA)
        let after = SVGWriter.write(rewritten)

        // Bound paints rewrote to the new colour in corpus formatting
        // (#222222 shortens to #222, like the writer does).
        XCTAssertTrue(after.contains("stroke: #222;"))
        XCTAssertTrue(after.contains("stop-color: #222;"))
        XCTAssertFalse(after.contains("#010101"))
        // Declaration order preserved on the edited node.
        XCTAssertTrue(after.contains("fill: none; stroke: #222; stroke-width: 4px;"))
        // Near-miss decoy untouched.
        XCTAssertTrue(after.contains("fill: #010102;"))

        // Untouched nodes are byte-identical: only lines carrying the old
        // colour (in any spelling) may differ.
        let beforeLines = before.split(separator: "\n", omittingEmptySubsequences: false)
        let afterLines = after.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(beforeLines.count, afterLines.count)
        for (b, a) in zip(beforeLines, afterLines) where b != a {
            XCTAssertTrue(
                b.contains("#010101") || b.contains("rgb(1,1,1)"),
                "untouched line changed: \(b)")
        }
    }

    func testSingleDocVariantReturnsNilWhenUnchanged() {
        var doc = GraphicDocument.blank(width: 72, height: 72)
        doc.nodes = [
            .shape(
                ShapeNode(
                    id: 0, kind: .circle(center: Pt(36, 36), r: 18),
                    style: SVGStyle.parse("fill: #ed2024;")))
        ]
        // No bound paint for this token.
        XCTAssertNil(StyleTokens.apply(tokens: tokens, changing: "outline", to: "#222", doc: doc))
        // Unknown token.
        XCTAssertNil(StyleTokens.apply(tokens: tokens, changing: "shadow", to: "#222", doc: doc))
        // Same colour, different spelling — no-op.
        XCTAssertNil(
            StyleTokens.apply(tokens: tokens, changing: "accent", to: "rgb(237,32,36)", doc: doc))
        // A real change does return a document.
        XCTAssertNotNil(
            StyleTokens.apply(tokens: tokens, changing: "accent", to: "#f00", doc: doc))
    }

    // MARK: Draw-with-style

    func testStyleForTokenNames() {
        let style = StyleTokens.style(
            for: ["stroke": "outline", "fill": "accent"], tokens: tokens)
        XCTAssertEqual(style.stroke, .color(r: 1, g: 1, b: 1))
        XCTAssertEqual(style.fill, .color(r: 237, g: 32, b: 36))

        // Base declarations update in place; new properties append.
        let base = SVGStyle.parse("fill: none; stroke-width: 4px;")
        let merged = StyleTokens.style(for: ["stroke": "outline"], tokens: tokens, base: base)
        XCTAssertEqual(
            SVGStyle.serialize(merged), "fill: none; stroke-width: 4px; stroke: #010101;")

        // Unknown token names are skipped.
        let skipped = StyleTokens.style(for: ["fill": "missing"], tokens: tokens, base: base)
        XCTAssertEqual(skipped, base)
    }

    // MARK: Realism — real open-icon fixtures

    func fixture(_ name: String) throws -> GraphicDocument {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "Fixtures/openicon/\(name)", withExtension: "svg")
                ?? Bundle.module.url(
                    forResource: name, withExtension: "svg", subdirectory: "Fixtures/openicon"),
            "missing fixture \(name)")
        return try SVGReader.read(try String(contentsOf: url, encoding: .utf8))
    }

    func testOpenIconFixturesBindCompletely() throws {
        for name in ["animals_icon_animal-step", "icon_fridge"] {
            let doc = try fixture(name)
            let found = StyleTokens.bindings(in: doc, tokens: tokens)
            XCTAssertFalse(found.isEmpty, name)
            // The corpus guarantee: every colour in the file is one of the
            // two slots, so nothing is left unbound.
            XCTAssertEqual(StyleTokens.unboundColors(in: doc, tokens: tokens), [], name)
            XCTAssertTrue(found.allSatisfy { $0.token == "outline" || $0.token == "accent" })

            // Retheme outline → #333: the doc changes, every old outline
            // paint rewrites, accent stays.
            let rethemed = try XCTUnwrap(
                StyleTokens.apply(tokens: tokens, changing: "outline", to: "#333", doc: doc),
                name)
            let out = SVGWriter.write(rethemed)
            XCTAssertFalse(out.contains("#010101"), name)
            XCTAssertTrue(out.contains("stroke: #333;"), name)
            XCTAssertTrue(out.contains("#ed2024"), name)

            // Untouched lines byte-identical to the pre-retheme write.
            let beforeLines = SVGWriter.write(doc).split(separator: "\n")
            let afterLines = out.split(separator: "\n")
            XCTAssertEqual(beforeLines.count, afterLines.count, name)
            for (b, a) in zip(beforeLines, afterLines) where b != a {
                XCTAssertTrue(b.contains("#010101"), "\(name): untouched line changed: \(b)")
            }
        }
    }
}
