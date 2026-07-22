import XCTest

@testable import FekthorKit

final class ContainerTests: XCTestCase {

    // MARK: Helpers

    private func slot(
        _ x: Double, _ y: Double, _ w: Double, _ h: Double, fit: String? = nil
    ) -> Workfile.ContainerSlot {
        Workfile.ContainerSlot(container: "c", x: x, y: y, width: w, height: h, fit: fit)
    }

    private func contentDoc(_ viewBox: ViewBox) -> GraphicDocument {
        var doc = GraphicDocument.blank(width: viewBox.width, height: viewBox.height)
        doc.viewBox = viewBox
        doc.nodes = [
            .shape(
                ShapeNode(
                    id: 0, kind: .line(Pt(2, 12), Pt(22, 12)),
                    style: SVGStyle.parse("fill: none; stroke: #010101; stroke-width: 4px;")))
        ]
        return doc
    }

    private func containerDoc() -> GraphicDocument {
        var doc = GraphicDocument.blank(width: 72, height: 72, id: "badge")
        doc.nodes = [
            .shape(
                ShapeNode(
                    id: 0, kind: .circle(center: Pt(36, 36), r: 36),
                    style: SVGStyle.parse("fill: #010101;")))
        ]
        return doc
    }

    /// The wrapper group compose appends (always the last node).
    private func wrapperGroup(_ doc: GraphicDocument) -> GroupNode? {
        guard case .group(let g)? = doc.nodes.last else { return nil }
        return g
    }

    // MARK: FitRule parsing

    func testFitRuleParsingIsForgiving() {
        XCTAssertEqual(FitRule.parse(nil), .contain)
        XCTAssertEqual(FitRule.parse(""), .contain)
        XCTAssertEqual(FitRule.parse("contain"), .contain)
        XCTAssertEqual(FitRule.parse(" COVER "), .cover)
        XCTAssertEqual(FitRule.parse("Stretch"), .stretch)
        XCTAssertEqual(FitRule.parse("fill"), .stretch)
        XCTAssertEqual(FitRule.parse("center"), .center)
        XCTAssertEqual(FitRule.parse("none"), .center)
        XCTAssertEqual(FitRule.parse("banana"), .contain)
    }

    // MARK: Slot transforms (exact numbers)

    func testContainSquareIntoWideSlot() {
        // 24x24 into 40x20 at (30,10): scale 20/24, centered horizontally.
        let t = Containers.slotTransform(
            contentViewBox: ViewBox(width: 24, height: 24), slot: slot(30, 10, 40, 20))
        let s = 20.0 / 24.0
        XCTAssertEqual(t?.matrix, [s, 0, 0, s, 40, 10])
        XCTAssertEqual(t?.raw, "translate(40 10) scale(.833333)")
    }

    func testCoverSquareIntoWideSlot() {
        // 24x24 into 40x20 at (30,10): scale 40/24, overflows vertically.
        let t = Containers.slotTransform(
            contentViewBox: ViewBox(width: 24, height: 24),
            slot: slot(30, 10, 40, 20, fit: "cover"))
        let s = 40.0 / 24.0
        XCTAssertEqual(t?.matrix, [s, 0, 0, s, 30, 0])
        XCTAssertEqual(t?.raw, "translate(30 0) scale(1.666667)")
    }

    func testContainAndCoverWideContentIntoTallSlot() {
        let wide = ViewBox(width: 40, height: 20)
        let tall = slot(0, 0, 20, 40)
        let contain = Containers.slotTransform(contentViewBox: wide, slot: tall)
        XCTAssertEqual(contain?.matrix, [0.5, 0, 0, 0.5, 0, 15])
        XCTAssertEqual(contain?.raw, "translate(0 15) scale(.5)")

        var coverSlot = tall
        coverSlot.fit = "cover"
        let cover = Containers.slotTransform(contentViewBox: wide, slot: coverSlot)
        XCTAssertEqual(cover?.matrix, [2, 0, 0, 2, -30, 0])
        XCTAssertEqual(cover?.raw, "translate(-30 0) scale(2)")
    }

    func testContainAndCoverTallContentIntoWideSlot() {
        let tallContent = ViewBox(width: 20, height: 40)
        let wide = slot(0, 0, 40, 20)
        let contain = Containers.slotTransform(contentViewBox: tallContent, slot: wide)
        XCTAssertEqual(contain?.matrix, [0.5, 0, 0, 0.5, 15, 0])

        var coverSlot = wide
        coverSlot.fit = "cover"
        let cover = Containers.slotTransform(contentViewBox: tallContent, slot: coverSlot)
        XCTAssertEqual(cover?.matrix, [2, 0, 0, 2, 0, -30])
    }

    func testStretchScalesAxesIndependently() {
        let t = Containers.slotTransform(
            contentViewBox: ViewBox(width: 24, height: 24),
            slot: slot(30, 10, 40, 20, fit: "stretch"))
        XCTAssertEqual(t?.matrix, [40.0 / 24.0, 0, 0, 20.0 / 24.0, 30, 10])
        XCTAssertEqual(t?.raw, "translate(30 10) scale(1.666667 .833333)")
    }

    func testCenterTranslatesWithoutScaling() {
        let t = Containers.slotTransform(
            contentViewBox: ViewBox(width: 24, height: 24),
            slot: slot(30, 10, 40, 20, fit: "center"))
        XCTAssertEqual(t?.matrix, [1, 0, 0, 1, 38, 8])
        XCTAssertEqual(t?.raw, "translate(38 8)")
    }

    func testNonZeroViewBoxOriginIsCompensated() {
        // Content viewBox "10 10 24 24" contained into the same slot: the
        // origin offset is scaled and subtracted.
        let s = 20.0 / 24.0
        let t = Containers.slotTransform(
            contentViewBox: ViewBox(minX: 10, minY: 10, width: 24, height: 24),
            slot: slot(30, 10, 40, 20))
        XCTAssertNotNil(t)
        XCTAssertEqual(t!.matrix[0], s)
        XCTAssertEqual(t!.matrix[3], s)
        XCTAssertEqual(t!.matrix[4], 40 - 10 * s, accuracy: 1e-12)
        XCTAssertEqual(t!.matrix[5], 10 - 10 * s, accuracy: 1e-12)
    }

    func testIdentityMappingProducesNoTransform() {
        let composed = Containers.compose(
            content: contentDoc(ViewBox(width: 24, height: 24)),
            into: containerDoc(), slot: slot(0, 0, 24, 24))
        XCTAssertNil(wrapperGroup(composed)?.transform)
    }

    // MARK: Compose structure

    func testComposeWrapsContentInOneGroupAfterContainerNodes() {
        let content = contentDoc(ViewBox(width: 24, height: 24))
        let container = containerDoc()
        let composed = Containers.compose(
            content: content, into: container, slot: slot(12, 12, 48, 48))

        // Container's viewBox and root attributes win; content root attrs drop.
        XCTAssertEqual(composed.viewBox, container.viewBox)
        XCTAssertEqual(composed.rootAttributes, container.rootAttributes)
        XCTAssertEqual(composed.nodes.count, container.nodes.count + 1)

        // Container nodes first (compare geometry/style, ids are reassigned).
        guard case .shape(let backdrop) = composed.nodes[0],
            case .shape(let original) = container.nodes[0]
        else { return XCTFail("container shape missing") }
        XCTAssertEqual(backdrop.kind, original.kind)
        XCTAssertEqual(backdrop.style, original.style)

        // Then ONE clean group wrap: content untouched inside, no baking.
        guard let group = wrapperGroup(composed) else { return XCTFail("wrapper group missing") }
        XCTAssertEqual(group.transform?.raw, "translate(12 12) scale(2)")
        XCTAssertEqual(group.transform?.matrix, [2, 0, 0, 2, 12, 12])
        XCTAssertEqual(group.children.count, 1)
        guard case .shape(let inner) = group.children[0],
            case .shape(let source) = content.nodes[0]
        else { return XCTFail("content shape missing") }
        XCTAssertEqual(inner.kind, source.kind)
        XCTAssertEqual(inner.style, source.style)
        XCTAssertNil(inner.transform)
    }

    func testComposedDocumentRoundTripsThroughWriterAndReader() throws {
        let composed = Containers.compose(
            content: contentDoc(ViewBox(width: 24, height: 24)),
            into: containerDoc(), slot: slot(12, 12, 48, 48))
        let svg = SVGWriter.write(composed)
        let reread = try SVGReader.read(svg)
        XCTAssertEqual(reread, composed)

        // The transform survives verbatim.
        guard let group = wrapperGroup(reread) else { return XCTFail("group missing") }
        XCTAssertEqual(group.transform?.raw, "translate(12 12) scale(2)")
        XCTAssertEqual(group.transform?.matrix, [2, 0, 0, 2, 12, 12])
    }

    func testComposedFractionalTransformSurvivesRoundTrip() throws {
        let composed = Containers.compose(
            content: contentDoc(ViewBox(width: 24, height: 24)),
            into: containerDoc(), slot: slot(30, 10, 40, 20))
        let reread = try SVGReader.read(SVGWriter.write(composed))
        guard let group = wrapperGroup(reread) else { return XCTFail("group missing") }
        XCTAssertEqual(group.transform?.raw, "translate(40 10) scale(.833333)")
        let m = try XCTUnwrap(group.transform?.matrix)
        XCTAssertEqual(m[0], 20.0 / 24.0, accuracy: 1e-6)
        XCTAssertEqual(m[3], 20.0 / 24.0, accuracy: 1e-6)
        XCTAssertEqual(m[4], 40)
        XCTAssertEqual(m[5], 10)
    }

    // MARK: Matrix export

    func testMatrixExportNamingAndDeterminism() throws {
        let icons = [
            "star": contentDoc(ViewBox(width: 24, height: 24)),
            "arrow": contentDoc(ViewBox(width: 24, height: 24)),
        ]
        let containers: [String: (GraphicDocument, Workfile.ContainerSlot)] = [
            "badge": (containerDoc(), slot(12, 12, 48, 48)),
            "circle": (containerDoc(), slot(16, 16, 40, 40)),
        ]
        let memberships = ["arrow": ["circle", "badge"], "star": ["badge"]]

        let exports = try Containers.matrixExports(
            icons: icons, containers: containers, memberships: memberships)
        XCTAssertEqual(
            exports.map(\.fileName),
            ["arrow-badge.svg", "arrow-circle.svg", "star-badge.svg"])

        // Deterministic: same inputs, byte-identical output.
        let again = try Containers.matrixExports(
            icons: icons, containers: containers, memberships: memberships)
        XCTAssertEqual(exports.map(\.fileName), again.map(\.fileName))
        XCTAssertEqual(exports.map { SVGWriter.write($0.doc) }, again.map { SVGWriter.write($0.doc) })

        // Editing the container once updates every composed export.
        for export in exports where export.fileName.hasSuffix("-badge.svg") {
            guard case .shape(let backdrop) = export.doc.nodes[0] else {
                return XCTFail("backdrop missing in \(export.fileName)")
            }
            XCTAssertEqual(backdrop.kind, .circle(center: Pt(36, 36), r: 36))
        }
    }

    func testMatrixExportUnknownContainersThrowTypedError() {
        let icons = ["arrow": contentDoc(ViewBox(width: 24, height: 24))]
        let containers: [String: (GraphicDocument, Workfile.ContainerSlot)] = [
            "badge": (containerDoc(), slot(12, 12, 48, 48))
        ]
        let memberships = ["arrow": ["zzz", "badge", "nope"]]
        XCTAssertThrowsError(
            try Containers.matrixExports(
                icons: icons, containers: containers, memberships: memberships)
        ) { error in
            XCTAssertEqual(
                error as? Containers.ExportError, .unknownContainers(["nope", "zzz"]))
        }
    }

    // MARK: Workfile memberships

    func testWorkfileRoundTripsContainerMemberships() throws {
        let wf = Workfile(
            containers: [
                .init(container: "badge", x: 12, y: 12, width: 48, height: 48, fit: "contain")
            ],
            containerMemberships: ["arrow-left": ["badge", "circle"], "star": ["badge"]])
        let data = try wf.encoded()
        XCTAssertEqual(try Workfile.decode(data), wf)
        XCTAssertEqual(data, try wf.encoded())  // byte determinism
        XCTAssertTrue(
            String(decoding: data, as: UTF8.self).contains("\"containerMemberships\""))

        // Old files without the key still decode (Codable tolerance intact).
        let old = try Workfile.decode(Data("{\"version\": 1}".utf8))
        XCTAssertNil(old.containerMemberships)
    }
}
