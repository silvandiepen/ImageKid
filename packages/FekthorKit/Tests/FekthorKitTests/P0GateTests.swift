import XCTest

@testable import FekthorKit

/// The P0 acceptance gate (EDITOR-PLAN step 10), engine-level: open a real
/// open-icon fixture, move one anchor, save; the file re-opens with the edit
/// intact, untouched nodes unchanged, and a second save is byte-identical.
final class P0GateTests: XCTestCase {
    func testEditSaveReopenGate() throws {
        guard
            let dir = Bundle.module.url(forResource: "Fixtures/openicon", withExtension: nil)
                ?? Bundle.module.url(forResource: "openicon", withExtension: nil, subdirectory: "Fixtures"),
            let url = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ).first(where: { $0.lastPathComponent == "arrows_icon_arrow-corner-down.svg" })
        else { return XCTFail("fixture missing") }
        let original = try String(contentsOf: url, encoding: .utf8)
        var doc = try SVGReader.read(original)

        func firstShapeID(_ nodes: [GraphicNode]) -> Int? {
            for n in nodes {
                switch n {
                case .shape(let s): return s.id
                case .group(let g): if let id = firstShapeID(g.children) { return id }
                default: break
                }
            }
            return nil
        }
        let id = try XCTUnwrap(firstShapeID(doc.nodes))
        let shape = try XCTUnwrap(doc.firstShape(id: id))
        let anchors = Editing2.anchors(of: shape)
        let target = Pt(anchors[0].position.x + 1, anchors[0].position.y + 1)
        doc.replaceShape(id: id, with: Editing2.moveAnchor(shape, path: 0, anchor: 0, to: target))

        let saved = SVGWriter.write(doc)
        let reopened = try SVGReader.read(saved)
        // Second save byte-identical.
        XCTAssertEqual(SVGWriter.write(reopened), saved)
        // Edit persisted.
        let reshaped = try XCTUnwrap(reopened.firstShape(id: id))
        let a2 = Editing2.anchors(of: reshaped)
        XCTAssertEqual(a2[0].position.x, target.x, accuracy: 0.01)
        XCTAssertEqual(a2[0].position.y, target.y, accuracy: 0.01)
        // Untouched structure preserved.
        let originalDoc = try SVGReader.read(original)
        XCTAssertEqual(originalDoc.nodes.count, reopened.nodes.count)
        // The saved text is valid standalone SVG (root + viewBox intact).
        XCTAssertTrue(saved.contains("viewBox=\"0 0 72 72\""))
    }
}
