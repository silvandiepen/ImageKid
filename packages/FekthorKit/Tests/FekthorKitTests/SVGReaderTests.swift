import XCTest

@testable import FekthorKit

final class SVGReaderTests: XCTestCase {
    func testRealCorpusShape() throws {
        // Structure copied from open-icon lib/icons/add-m.svg
        let svg = """
            <svg id="add-m" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 72"><line x1="36" y1="18" x2="36" y2="54" style="fill: none; stroke-miterlimit: 10; stroke-width: 4px;"/><line x1="18" y1="36" x2="54" y2="36" style="fill: none; stroke: #010101;"/></svg>
            """
        let doc = try SVGReader.read(svg)
        XCTAssertEqual(doc.viewBox.width, 72)
        XCTAssertFalse(doc.hadXMLDeclaration)
        XCTAssertEqual(doc.rootAttributes.first, XMLAttr(name: "id", value: "add-m"))
        XCTAssertEqual(doc.nodes.count, 2)
        guard case .shape(let line) = doc.nodes[0], case .line(let a, let b) = line.kind else {
            return XCTFail()
        }
        XCTAssertEqual(a, Pt(36, 18))
        XCTAssertEqual(b, Pt(36, 54))
        XCTAssertEqual(line.style.strokeWidth, 4)
        guard case .shape(let l2) = doc.nodes[1] else { return XCTFail() }
        XCTAssertEqual(l2.style.stroke, .color(r: 1, g: 1, b: 1))
        // Two reads are equal (deterministic ids).
        XCTAssertEqual(doc, try SVGReader.read(svg))
    }

    func testRawSourceIconWithDeclarationGroupsAndDataName() throws {
        let svg = """
            <?xml version="1.0" encoding="UTF-8"?>
            <svg id="elevator_4" data-name="elevator 4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 72">
              <g style="opacity: .5;" transform="translate(2 3)">
                <path d="M30.7,46.19v7.14c0,.55.45,1,1,1h4.3Z" style="fill: none; stroke: #ed2024; stroke-width: 4px;"/>
                <rect x="10" y="12" width="20" height="8" rx="2" style="fill: #010101;"/>
              </g>
              <circle cx="36" cy="36" r="5" style="fill: #ed2024; opacity: .5;"/>
            </svg>
            """
        let doc = try SVGReader.read(svg)
        XCTAssertTrue(doc.hadXMLDeclaration)
        XCTAssertEqual(doc.rootAttributes.count, 3)  // id, xmlns, (data-name sorted after)
        XCTAssertEqual(doc.nodes.count, 2)
        guard case .group(let g) = doc.nodes[0] else { return XCTFail() }
        XCTAssertEqual(g.style.opacity, 0.5)
        XCTAssertNotNil(g.transform)
        XCTAssertEqual(g.transform!.apply(Pt(0, 0)), Pt(2, 3))
        XCTAssertEqual(g.children.count, 2)
        guard case .shape(let rect) = g.children[1],
            case .rect(_, _, _, _, let rx, _) = rect.kind
        else { return XCTFail() }
        XCTAssertEqual(rx, 2)
        guard case .shape(let path) = g.children[0], case .path(let paths) = path.kind else {
            return XCTFail()
        }
        XCTAssertTrue(paths[0].closed)
    }

    func testRawPassthroughAndClassResolution() throws {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 72">
              <defs><clipPath id="c0"><rect width="10" height="10"/></clipPath></defs>
              <style>.st0 { fill: none; stroke: #010101; } .st1{fill:#ed2024;}</style>
              <path class="st0" d="M0,0L10,10"/>
              <polygon class="st1" points="0,0 4,0 4,4"/>
            </svg>
            """
        let doc = try SVGReader.read(svg)
        XCTAssertEqual(doc.nodes.count, 4)
        guard case .raw(let defs) = doc.nodes[0] else { return XCTFail() }
        XCTAssertTrue(defs.xml.contains("<defs>"))
        XCTAssertTrue(defs.xml.contains("clipPath"))
        guard case .raw(let styleBlock) = doc.nodes[1] else { return XCTFail() }
        XCTAssertTrue(styleBlock.xml.hasPrefix("<style>"))
        guard case .shape(let p) = doc.nodes[2] else { return XCTFail() }
        // Inline style empty; class-resolved style renders.
        XCTAssertTrue(p.style.declarations.isEmpty)
        XCTAssertEqual(p.effectiveStyle.stroke, .color(r: 1, g: 1, b: 1))
        guard case .shape(let poly) = doc.nodes[3], case .polygon(let pts) = poly.kind else {
            return XCTFail()
        }
        XCTAssertEqual(pts.count, 3)
        XCTAssertEqual(poly.effectiveStyle.fill, .color(r: 237, g: 32, b: 36))
    }

    func testTransformParsing() {
        let t = SVGReader.parseTransform("rotate(90 36 36)")!
        let p = t.apply(Pt(36, 18))
        XCTAssertEqual(p.x, 54, accuracy: 1e-9)
        XCTAssertEqual(p.y, 36, accuracy: 1e-9)
        let m = SVGReader.parseTransform("matrix(1 0 0 1 5 6)")!
        XCTAssertEqual(m.apply(Pt(0, 0)), Pt(5, 6))
        let combo = SVGReader.parseTransform("translate(10) scale(2)")!
        XCTAssertEqual(combo.apply(Pt(1, 1)), Pt(12, 2))
        XCTAssertNil(SVGReader.parseTransform("garbage"))
    }

    func testCorpusSmoke() throws {
        guard let root = ProcessInfo.processInfo.environment["FEKTHOR_ICON_CORPUS"] else {
            throw XCTSkip("set FEKTHOR_ICON_CORPUS to run")
        }
        let fm = FileManager.default
        var failures: [String] = []
        var count = 0
        if let e = fm.enumerator(atPath: root) {
            for case let rel as String in e where rel.hasSuffix(".svg") {
                let path = root + "/" + rel
                guard let data = fm.contents(atPath: path) else { continue }
                count += 1
                do { _ = try SVGReader.read(data) } catch { failures.append(rel) }
            }
        }
        XCTAssertTrue(count > 0, "no svgs found under \(root)")
        XCTAssertEqual(failures, [], "\(failures.count)/\(count) failed")
        print("corpus smoke: parsed \(count) files, 0 errors")
    }
}
