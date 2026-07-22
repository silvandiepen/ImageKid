import XCTest

@testable import FekthorKit

final class SVGPathDataTests: XCTestCase {
    func flat(_ paths: [RefinedPath]) -> [Pt] {
        paths.flatMap { PathRefine.flatten($0) }
    }

    func testBasicAbsoluteAndRelative() throws {
        let paths = try SVGPathData.parse("M10 10 L20 10 l0 10 H10 V10 Z")
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths[0].closed)
        XCTAssertEqual(paths[0].segments.count, 4)
        XCTAssertEqual(paths[0].segments[1].endPoint, Pt(20, 20))
    }

    func testCompactNumbersAndImplicitRepeats() throws {
        // Corpus style: omitted leading zeros, packed negatives, implicit L after M.
        let paths = try SVGPathData.parse("M30.7,46.19v7.14c0,.55.45,1,1,1h4.3")
        XCTAssertEqual(paths.count, 1)
        let segs = paths[0].segments
        XCTAssertEqual(segs.count, 3)
        XCTAssertEqual(segs[0].endPoint, Pt(30.7, 53.33))
        if case .cubic(let c1, _, let to) = segs[1] {
            XCTAssertEqual(c1.x, 30.7, accuracy: 1e-9)
            XCTAssertEqual(c1.y, 53.88, accuracy: 1e-9)
            XCTAssertEqual(to.x, 31.7, accuracy: 1e-9)
            XCTAssertEqual(to.y, 54.33, accuracy: 1e-9)
        } else {
            XCTFail()
        }
        // "-3-4" packing + exponent form
        let p2 = try SVGPathData.parse("M0 0l-3-4 5e-2.5")
        XCTAssertEqual(p2[0].segments.count, 2)
        XCTAssertEqual(p2[0].segments[0].endPoint, Pt(-3, -4))
        XCTAssertEqual(p2[0].segments[1].endPoint.x, -2.95, accuracy: 1e-9)
        XCTAssertEqual(p2[0].segments[1].endPoint.y, -3.5, accuracy: 1e-9)
    }

    func testSmoothAndQuadratic() throws {
        let s = try SVGPathData.parse("M0 0 C0 10 10 10 10 0 S20 -10 20 0")
        if case .cubic(let c1, _, _) = s[0].segments[1] {
            // Reflection of (10,10) about (10,0):
            XCTAssertEqual(c1, Pt(10, -10))
        } else {
            XCTFail()
        }
        let q = try SVGPathData.parse("M0 0 Q5 10 10 0 T20 0")
        XCTAssertEqual(q[0].segments.count, 2)
        if case .cubic(let c1, _, _) = q[0].segments[1] {
            // T reflects the previous quad control (5,10) about (10,0) → (15,-10),
            // elevated c1 = current + 2/3*(q - current).
            XCTAssertEqual(c1.x, 10 + 2.0 / 3.0 * 5, accuracy: 1e-9)
            XCTAssertEqual(c1.y, 2.0 / 3.0 * -10, accuracy: 1e-9)
        } else {
            XCTFail()
        }
    }

    func testCircularArcBecomesTypedArc() throws {
        let paths = try SVGPathData.parse("M10 0 A10 10 0 0 1 0 10")
        guard case .arc(let c, let r, _, _, _) = paths[0].segments[0] else {
            return XCTFail("expected typed arc")
        }
        XCTAssertEqual(r, 10, accuracy: 1e-9)
        XCTAssertEqual(c.x, 0, accuracy: 1e-6)
        XCTAssertEqual(c.y, 0, accuracy: 1e-6)
        // Elliptical arc approximates with cubics, endpoint exact.
        let e = try SVGPathData.parse("M10 0 A10 5 0 0 1 0 5")
        XCTAssertFalse(e[0].segments.contains { if case .arc = $0 { return true } else { return false } })
        XCTAssertEqual(e[0].segments.last!.endPoint.x, 0, accuracy: 1e-6)
        XCTAssertEqual(e[0].segments.last!.endPoint.y, 5, accuracy: 1e-6)
    }

    func testMultipleSubpathsAndZContinuation() throws {
        let paths = try SVGPathData.parse("M0 0 L10 0 Z M20 0 L30 0")
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths[0].closed)
        XCTAssertFalse(paths[1].closed)
    }

    func testSerializeParsesBack() throws {
        let original = try SVGPathData.parse("M30.7,46.19v7.14c0,.55.45,1,1,1h4.3Z")
        let text = SVGPathData.serialize(original, emitArcs: false)
        let reparsed = try SVGPathData.parse(text)
        XCTAssertEqual(original.count, reparsed.count)
        let a = flat(original)
        let b = flat(reparsed)
        XCTAssertEqual(a.count, b.count)
        for (p, q) in zip(a, b) {
            XCTAssertEqual(p.x, q.x, accuracy: 0.02)
            XCTAssertEqual(p.y, q.y, accuracy: 0.02)
        }
        // Serialization is deterministic.
        XCTAssertEqual(text, SVGPathData.serialize(original, emitArcs: false))
    }
}

final class SVGStyleTests: XCTestCase {
    func testCorpusStyleStringsRoundTripVerbatim() {
        let corpus = [
            "fill: none; stroke: #010101; stroke-linejoin: round; stroke-width: 4px;",
            "fill: #ed2024; opacity: .5; stroke-width: 0px;",
            "fill: none; stroke: #ed2024; stroke-miterlimit: 10; stroke-width: 4px;",
            "fill: none; stroke: #010101; stroke-linecap: round; stroke-linejoin: round; stroke-width: 4px;",
            "fill: #fff; stroke: #010101; stroke-miterlimit: 10;",
            "fill: none; stroke-miterlimit: 10; stroke-width:var(--icon-stroke-width-m, calc(var(--icon-stroke-width, 5) * 1));",
            "fill: var(--icon-fill, rgba(0,0,0,0)); stroke: var(--icon-stroke-color, currentColor);",
        ]
        for text in corpus {
            let parsed = SVGStyle.parse(text)
            let out = SVGStyle.serialize(parsed)
            // Canonical spacing: single space after colon and between decls.
            let normalized = text
                .split(separator: ";").map {
                    $0.split(separator: ":", maxSplits: 1)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .joined(separator: ": ")
                }
                .filter { !$0.isEmpty }
                .map { $0 + ";" }
                .joined(separator: " ")
            XCTAssertEqual(out, normalized, "round-trip failed for: \(text)")
        }
    }

    func testTypedParsing() {
        let s = SVGStyle.parse("fill: none; stroke: #ed2024; stroke-width: 4px; opacity: .5")
        XCTAssertEqual(s.fill, PaintValue.none)
        XCTAssertEqual(s.stroke, .color(r: 237, g: 32, b: 36))
        XCTAssertEqual(s.strokeWidth, 4)
        XCTAssertEqual(s.opacity, 0.5)
        // var() stays raw and verbatim.
        let v = SVGStyle.parse("stroke: var(--icon-stroke-color, currentColor);")
        if case .raw(let raw)? = v.stroke {
            XCTAssertEqual(raw, "var(--icon-stroke-color, currentColor)")
        } else {
            XCTFail()
        }
        // url reference
        let u = SVGStyle.parse("fill: url(#grad-0);")
        XCTAssertEqual(u.fill, .reference("grad-0"))
        // Shorthand hex #fff survives as #fff.
        let w = SVGStyle.parse("fill: #fff;")
        XCTAssertEqual(SVGStyle.serialize(w), "fill: #fff;")
    }
}
