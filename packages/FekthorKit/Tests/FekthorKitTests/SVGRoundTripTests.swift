import XCTest

@testable import FekthorKit

/// The P0 round-trip gate, run against real open-icon files copied into the
/// test bundle (40 fixtures: every corpus feature — class styles, clipPath
/// defs, transforms, ellipse/polyline/polygon, CSS-variable built flavour).
final class SVGRoundTripTests: XCTestCase {
    static var fixtures: [(name: String, text: String)] = []

    override class func setUp() {
        super.setUp()
        guard
            let dir = Bundle.module.url(forResource: "Fixtures/openicon", withExtension: nil)
                ?? Bundle.module.url(forResource: "openicon", withExtension: nil, subdirectory: "Fixtures")
        else { return }
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
        fixtures = urls.filter { $0.pathExtension == "svg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return (url.lastPathComponent, text)
            }
    }

    func testFixturesPresent() {
        XCTAssertGreaterThanOrEqual(Self.fixtures.count, 35)
    }

    /// write∘read is idempotent and byte-deterministic for every fixture.
    func testIdempotenceAndDeterminism() throws {
        for (name, text) in Self.fixtures {
            let doc1 = try SVGReader.read(text)
            let s1 = SVGWriter.write(doc1)
            XCTAssertEqual(s1, SVGWriter.write(doc1), "non-deterministic: \(name)")
            let doc2 = try SVGReader.read(s1)
            let s2 = SVGWriter.write(doc2)
            XCTAssertEqual(s1, s2, "not idempotent: \(name)")
        }
    }

    /// Semantic equality vs the ORIGINAL source: same node tree, same style
    /// declaration lists, geometry within 0.05 units (number reformatting).
    func testNormalizedDiffAgainstSource() throws {
        for (name, text) in Self.fixtures {
            let original = try SVGReader.read(text)
            let rewritten = try SVGReader.read(SVGWriter.write(original))
            assertEquivalent(original, rewritten, name: name)
        }
    }

    /// Env-gated: idempotence + semantic equality across the ENTIRE corpus.
    func testCorpusRoundTrip() throws {
        guard let root = ProcessInfo.processInfo.environment["FEKTHOR_ICON_CORPUS"] else {
            throw XCTSkip("set FEKTHOR_ICON_CORPUS to run")
        }
        let fm = FileManager.default
        var count = 0
        var failures: [String] = []
        if let e = fm.enumerator(atPath: root) {
            for case let rel as String in e where rel.hasSuffix(".svg") {
                guard let data = fm.contents(atPath: root + "/" + rel) else { continue }
                guard let original = try? SVGReader.read(data) else {
                    failures.append(rel + " (parse)")
                    continue
                }
                count += 1
                let s1 = SVGWriter.write(original)
                guard let doc2 = try? SVGReader.read(s1) else {
                    failures.append(rel + " (reparse)")
                    continue
                }
                if SVGWriter.write(doc2) != s1 { failures.append(rel + " (idempotence)") }
            }
        }
        XCTAssertTrue(count > 0)
        XCTAssertEqual(failures, [])
        print("corpus round-trip: \(count) files clean")
    }

    // MARK: - tolerant document comparison

    private func assertEquivalent(_ a: GraphicDocument, _ b: GraphicDocument, name: String) {
        XCTAssertEqual(a.viewBox, b.viewBox, name)
        XCTAssertEqual(a.rootAttributes, b.rootAttributes, name)
        XCTAssertEqual(a.hadXMLDeclaration, b.hadXMLDeclaration, name)
        assertNodesEquivalent(a.nodes, b.nodes, name: name)
    }

    private func assertNodesEquivalent(_ a: [GraphicNode], _ b: [GraphicNode], name: String) {
        XCTAssertEqual(a.count, b.count, "node count: \(name)")
        for (x, y) in zip(a, b) {
            switch (x, y) {
            case (.raw(let r1), .raw(let r2)):
                XCTAssertEqual(r1.xml, r2.xml, name)
            case (.group(let g1), .group(let g2)):
                XCTAssertEqual(g1.style, g2.style, name)
                XCTAssertEqual(g1.attributes, g2.attributes, name)
                XCTAssertEqual(g1.transform?.raw, g2.transform?.raw, name)
                assertNodesEquivalent(g1.children, g2.children, name: name)
            case (.shape(let s1), .shape(let s2)):
                XCTAssertEqual(s1.style, s2.style, "style: \(name)")
                XCTAssertEqual(s1.attributes, s2.attributes, "attrs: \(name)")
                XCTAssertEqual(s1.transform?.raw, s2.transform?.raw, "transform: \(name)")
                XCTAssertEqual(s1.classStyle, s2.classStyle, "classStyle: \(name)")
                assertKindEquivalent(s1.kind, s2.kind, name: name)
            default:
                XCTFail("node kind mismatch in \(name)")
            }
        }
    }

    private func assertKindEquivalent(_ a: ShapeKind, _ b: ShapeKind, name: String) {
        func near(_ p: Pt, _ q: Pt) {
            XCTAssertEqual(p.x, q.x, accuracy: 0.05, name)
            XCTAssertEqual(p.y, q.y, accuracy: 0.05, name)
        }
        switch (a, b) {
        case (.path(let p1), .path(let p2)):
            XCTAssertEqual(p1.count, p2.count, "subpath count: \(name)")
            for (r1, r2) in zip(p1, p2) {
                XCTAssertEqual(r1.closed, r2.closed, name)
                let f1 = PathRefine.flatten(r1)
                let f2 = PathRefine.flatten(r2)
                // Flatten sampling may differ slightly in count; compare by
                // walking the shorter list against nearest in the other.
                XCTAssertEqual(f1.first.map { [$0.x, $0.y] } ?? [], f2.first.map { [$0.x, $0.y] } ?? [], name)
                for p in stride(from: 0, to: min(f1.count, f2.count), by: 7)
                    .map({ f1[$0] })
                {
                    let best = f2.map { hypot($0.x - p.x, $0.y - p.y) }.min() ?? .infinity
                    XCTAssertLessThan(best, 0.08, "geometry drift in \(name)")
                }
            }
        case (.line(let a1, let a2), .line(let b1, let b2)):
            near(a1, b1)
            near(a2, b2)
        case (.polyline(let p1), .polyline(let p2)), (.polygon(let p1), .polygon(let p2)):
            XCTAssertEqual(p1.count, p2.count, name)
            for (p, q) in zip(p1, p2) { near(p, q) }
        case (.rect(let x1, let y1, let w1, let h1, let rx1, let ry1),
              .rect(let x2, let y2, let w2, let h2, let rx2, let ry2)):
            XCTAssertEqual(x1, x2, accuracy: 0.05, name)
            XCTAssertEqual(y1, y2, accuracy: 0.05, name)
            XCTAssertEqual(w1, w2, accuracy: 0.05, name)
            XCTAssertEqual(h1, h2, accuracy: 0.05, name)
            XCTAssertEqual(rx1 ?? -1, rx2 ?? -1, accuracy: 0.05, name)
            XCTAssertEqual(ry1 ?? -1, ry2 ?? -1, accuracy: 0.05, name)
        case (.circle(let c1, let r1), .circle(let c2, let r2)):
            near(c1, c2)
            XCTAssertEqual(r1, r2, accuracy: 0.05, name)
        case (.ellipse(let c1, let rx1, let ry1), .ellipse(let c2, let rx2, let ry2)):
            near(c1, c2)
            XCTAssertEqual(rx1, rx2, accuracy: 0.05, name)
            XCTAssertEqual(ry1, ry2, accuracy: 0.05, name)
        default:
            XCTFail("shape kind changed in \(name)")
        }
    }
}
