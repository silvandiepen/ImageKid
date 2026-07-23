import XCTest

@testable import FekthorKit

final class FileMetaTests: XCTestCase {
    private func blankDoc() -> GraphicDocument {
        var doc = GraphicDocument.blank(width: 72, height: 72)
        doc.nodes.append(
            .shape(
                ShapeNode(
                    id: 0, kind: .rect(x: 8, y: 8, width: 56, height: 56, rx: nil, ry: nil),
                    style: SVGStyle.parse("fill: #ff0000"))))
        return doc
    }

    func testWriteReadRoundTripInMemory() {
        let meta = FileMeta.Meta(
            swatches: ["#ff0000", "#00ff88"],
            styles: [NamedStyle(name: "brand", declarations: ["fill": "#ff0000"])])
        let doc = FileMeta.writing(meta, to: blankDoc())
        XCTAssertEqual(FileMeta.read(from: doc), meta)
    }

    func testRoundTripsThroughWriterAndReader() throws {
        let meta = FileMeta.Meta(
            swatches: ["#010101"],
            styles: [
                NamedStyle(
                    name: "line", declarations: ["stroke": "#010101", "stroke-width": "2"])
            ])
        let doc = FileMeta.writing(meta, to: blankDoc())
        let svg = SVGWriter.write(doc)
        XCTAssertTrue(svg.contains("<metadata id=\"fekthor-meta\">"))
        let reread = try SVGReader.read(svg)
        XCTAssertEqual(FileMeta.read(from: reread), meta)
        // Idempotent: save again, byte-identical metadata survives.
        let again = SVGWriter.write(FileMeta.writing(meta, to: reread))
        XCTAssertEqual(svg, again)
    }

    func testWritingReplacesExistingBlock() {
        let first = FileMeta.Meta(swatches: ["#111111"])
        let second = FileMeta.Meta(swatches: ["#222222", "#333333"])
        var doc = FileMeta.writing(first, to: blankDoc())
        doc = FileMeta.writing(second, to: doc)
        XCTAssertEqual(FileMeta.read(from: doc), second)
        // Only ONE metadata node exists.
        let metaNodes = doc.nodes.filter {
            if case .raw(let r) = $0 { return FileMeta.isMetaXML(r.xml) }
            return false
        }
        XCTAssertEqual(metaNodes.count, 1)
    }

    func testEmptyMetaRemovesBlock() {
        var doc = FileMeta.writing(FileMeta.Meta(swatches: ["#111111"]), to: blankDoc())
        doc = FileMeta.writing(FileMeta.Meta(), to: doc)
        XCTAssertNil(FileMeta.read(from: doc))
        XCTAssertFalse(SVGWriter.write(doc).contains("fekthor-meta"))
    }

    func testRemovingStripsOnlyTheMetaBlock() {
        var doc = FileMeta.writing(FileMeta.Meta(swatches: ["#111111"]), to: blankDoc())
        doc.nodes.append(.raw(RawNode(id: doc.nextNodeID, xml: "<title>hello</title>")))
        let stripped = FileMeta.removing(from: doc)
        XCTAssertNil(FileMeta.read(from: stripped))
        XCTAssertTrue(
            stripped.nodes.contains {
                if case .raw(let r) = $0 { return r.xml == "<title>hello</title>" }
                return false
            })
        XCTAssertEqual(stripped.nodes.count, doc.nodes.count - 1)
    }

    func testForeignMetadataIsLeftAlone() {
        var doc = blankDoc()
        doc.nodes.append(
            .raw(RawNode(id: doc.nextNodeID, xml: "<metadata id=\"other\">x</metadata>")))
        XCTAssertNil(FileMeta.read(from: doc))
        let stripped = FileMeta.removing(from: doc)
        XCTAssertEqual(stripped.nodes.count, doc.nodes.count)
    }

    func testEscapingSurvivesAmpersandsAndAngles() throws {
        // Style values could theoretically carry & or < — the block must
        // still round-trip through the writer/reader escape pair.
        let meta = FileMeta.Meta(
            styles: [NamedStyle(name: "odd", declarations: ["fill": "url(#a&b)"])])
        let doc = FileMeta.writing(meta, to: blankDoc())
        let reread = try SVGReader.read(SVGWriter.write(doc))
        XCTAssertEqual(FileMeta.read(from: reread), meta)
    }
}
