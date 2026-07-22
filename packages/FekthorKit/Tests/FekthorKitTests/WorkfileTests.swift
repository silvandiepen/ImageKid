import XCTest

@testable import FekthorKit

final class WorkfileTests: XCTestCase {
    func testRoundTripAndDeterminism() throws {
        let wf = Workfile(
            folder: .init(path: "icons"),
            artboards: [.init(name: "arrow-left", svg: "<svg viewBox=\"0 0 72 72\"/>")],
            categories: ["arrows", "ui"],
            exportProfiles: [.init(name: "web-outlined", actions: ["outlineStrokes"], output: "dist")],
            styleTokens: [.init(name: "outline", value: "#010101")],
            containers: [.init(container: "circle-badge", x: 12, y: 12, width: 48, height: 48, fit: "contain")])
        let data = try wf.encoded()
        XCTAssertEqual(try Workfile.decode(data), wf)
        XCTAssertEqual(data, try wf.encoded())  // byte determinism
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"version\" : 1"))
    }

    func testUnknownKeyTolerance() throws {
        let json = """
            {"version": 7, "futureFeature": {"nested": [1,2,3]}, "categories": ["x"]}
            """
        let wf = try Workfile.decode(Data(json.utf8))
        XCTAssertEqual(wf.version, 7)
        XCTAssertEqual(wf.categories, ["x"])
        XCTAssertNil(wf.artboards)
    }

    func testEmbeddedArtboardSVGSurvives() throws {
        var doc = GraphicDocument.blank(width: 72, height: 72, id: "icon")
        doc.nodes = [
            .shape(
                ShapeNode(
                    id: 0, kind: .line(Pt(18, 36), Pt(54, 36)),
                    style: SVGStyle.parse("fill: none; stroke: #010101; stroke-width: 4px;")))
        ]
        let svg = SVGWriter.write(doc)
        let wf = Workfile(artboards: [.init(name: "test", svg: svg)])
        let back = try Workfile.decode(try wf.encoded())
        let restored = try SVGReader.read(back.artboards![0].svg)
        XCTAssertEqual(restored, doc)
    }
}

extension WorkfileTests {
    func testNamedStylesSwatchesAndGuideRoundTrip() throws {
        var wf = Workfile()
        wf.namedStyles = [
            NamedStyle(
                name: "brand-stroke",
                declarations: [
                    "stroke": "#010101", "stroke-width": "4", "stroke-linecap": "round",
                    "stroke-linejoin": "miter", "fill": "none",
                ])
        ]
        wf.swatches = ["#010101", "#ed2024", "#fff"]
        wf.settings = .init(guideIcon: "grid-guide", showGuide: true)
        let data = try wf.encoded()
        XCTAssertEqual(try Workfile.decode(data), wf)
        XCTAssertEqual(data, try wf.encoded())  // byte determinism incl. declaration map

        // Old workfiles without the new keys decode with nils.
        let old = try Workfile.decode(Data("""
            {"version": 1, "settings": {"iconWidth": 24}}
            """.utf8))
        XCTAssertNil(old.namedStyles)
        XCTAssertNil(old.swatches)
        XCTAssertNil(old.settings?.guideIcon)
        XCTAssertNil(old.settings?.showGuide)
        XCTAssertEqual(old.settings?.iconWidth, 24)
    }

    func testWorkspaceSettingsRoundTripAndTolerance() throws {
        var wf = Workfile()
        wf.settings = .init(iconWidth: 24, iconHeight: 24, gridSpacing: 1, snapToGrid: true)
        let decoded = try Workfile.decode(wf.encoded())
        XCTAssertEqual(decoded, wf)
        // Old workfiles without the key decode with nil settings.
        let old = try Workfile.decode(Workfile().encoded())
        XCTAssertNil(old.settings)
        XCTAssertEqual(Workfile.WorkspaceSettings.standard.iconWidth, 24)
    }
}
