import CoreGraphics
import XCTest

@testable import FekthorKit

final class PathOpsTests: XCTestCase {
    // MARK: - Helpers

    /// Rectangle ring, positive shoelace orientation.
    func rectRing(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [Pt] {
        [Pt(x, y), Pt(x + w, y), Pt(x + w, y + h), Pt(x, y + h)]
    }

    func rectNode(_ id: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> ShapeNode {
        ShapeNode(id: id, kind: .rect(x: x, y: y, width: w, height: h, rx: nil, ry: nil))
    }

    func area(_ rings: [[Pt]]) -> Double { PathOps.regionArea(rings) }

    // MARK: - Exact cases: two overlapping rects

    func testUnionOverlappingRects() {
        let out = PathOps.clip(
            subject: [rectRing(0, 0, 10, 10)], clip: [rectRing(5, 5, 10, 10)], op: .union)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].count, 8, "corner-overlap union is an 8-vertex outline")
        XCTAssertEqual(area(out), 175, accuracy: 1e-3)
    }

    func testSubtractOverlappingRects() {
        let out = PathOps.clip(
            subject: [rectRing(0, 0, 10, 10)], clip: [rectRing(5, 5, 10, 10)], op: .subtract)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].count, 6, "corner subtraction is an L-shaped hexagon")
        XCTAssertEqual(area(out), 75, accuracy: 1e-3)
    }

    func testIntersectOverlappingRects() {
        let out = PathOps.clip(
            subject: [rectRing(0, 0, 10, 10)], clip: [rectRing(5, 5, 10, 10)], op: .intersect)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].count, 4)
        XCTAssertEqual(area(out), 25, accuracy: 1e-3)
    }

    func testExcludeOverlappingRects() {
        let out = PathOps.clip(
            subject: [rectRing(0, 0, 10, 10)], clip: [rectRing(5, 5, 10, 10)], op: .exclude)
        XCTAssertEqual(out.count, 2, "xor of corner-overlapping squares is two L-shapes")
        XCTAssertEqual(area(out), 150, accuracy: 1e-3)
    }

    func testIntersectDisjoint() {
        let out = PathOps.clip(
            subject: [rectRing(0, 0, 10, 10)], clip: [rectRing(20, 0, 5, 5)], op: .intersect)
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: - Identical inputs

    func testIdenticalShapesAllOps() {
        let r = [rectRing(3, 4, 10, 10)]
        let union = PathOps.clip(subject: r, clip: r, op: .union)
        XCTAssertEqual(union.count, 1)
        XCTAssertEqual(area(union), 100, accuracy: 1e-3)
        let intersect = PathOps.clip(subject: r, clip: r, op: .intersect)
        XCTAssertEqual(area(intersect), 100, accuracy: 1e-3)
        XCTAssertTrue(PathOps.clip(subject: r, clip: r, op: .subtract).isEmpty)
        XCTAssertTrue(PathOps.clip(subject: r, clip: r, op: .exclude).isEmpty)
    }

    // MARK: - Shared edges & vertex-on-edge

    func testSharedEdgeRects() {
        let a = [rectRing(0, 0, 10, 10)]
        let b = [rectRing(10, 0, 10, 10)]
        let union = PathOps.clip(subject: a, clip: b, op: .union)
        XCTAssertEqual(union.count, 1)
        XCTAssertEqual(union[0].count, 4, "shared edge dissolves; collinear vertices merge")
        XCTAssertEqual(area(union), 200, accuracy: 1e-3)
        XCTAssertTrue(
            PathOps.clip(subject: a, clip: b, op: .intersect).isEmpty,
            "shared edge alone has zero area")
        let sub = PathOps.clip(subject: a, clip: b, op: .subtract)
        XCTAssertEqual(area(sub), 100, accuracy: 1e-3)
    }

    func testTriangleVertexTouchingEdge() {
        let rect = [rectRing(0, 0, 10, 10)]
        let tri = [[Pt(10, 5), Pt(15, 0), Pt(15, 10)]]
        let union = PathOps.clip(subject: rect, clip: tri, op: .union)
        XCTAssertEqual(area(union), 125, accuracy: 1e-3)
        let sub = PathOps.clip(subject: rect, clip: tri, op: .subtract)
        XCTAssertEqual(area(sub), 100, accuracy: 1e-3)
        let inter = PathOps.clip(subject: rect, clip: tri, op: .intersect)
        XCTAssertTrue(inter.isEmpty || abs(area(inter)) < 1e-6)
    }

    // MARK: - Donut (evenodd holes) bridged by a rect

    func testDonutUnionBridgingRect() {
        // Even-odd donut: 20×20 outer, 10×10 hole → area 300.
        let donut = [rectRing(0, 0, 20, 20), rectRing(5, 5, 10, 10)]
        let bridge = [rectRing(8, 0, 4, 20)]
        let out = PathOps.clip(
            subject: donut, subjectRule: .evenOdd, clip: bridge, op: .union)
        // The bar splits the hole in two: outer ring + two holes.
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(area(out), 340, accuracy: 1e-3)
        let outer = out.filter { Geometry.signedArea($0) > 0 }
        let holes = out.filter { Geometry.signedArea($0) < 0 }
        XCTAssertEqual(outer.count, 1, "one positive outer ring")
        XCTAssertEqual(holes.count, 2, "two negative hole rings")
        XCTAssertEqual(Geometry.signedArea(outer[0]), 400, accuracy: 1e-3)
    }

    // MARK: - Fill rules

    func testNonZeroVersusEvenOddNesting() {
        let outer = rectRing(0, 0, 20, 20)
        let inner = rectRing(5, 5, 10, 10)
        let innerReversed: [Pt] = inner.reversed()
        // Same orientation + nonzero → winding 2 inside → solid square.
        let solid = PathOps.clip(
            subject: [outer, inner], subjectRule: .nonZero, clip: [], op: .union)
        XCTAssertEqual(area(solid), 400, accuracy: 1e-3)
        XCTAssertEqual(solid.count, 1)
        // Opposite orientation + nonzero → winding 0 inside → donut.
        let donut = PathOps.clip(
            subject: [outer, innerReversed], subjectRule: .nonZero, clip: [], op: .union)
        XCTAssertEqual(area(donut), 300, accuracy: 1e-3)
        XCTAssertEqual(donut.count, 2)
        // Even-odd ignores orientation → donut either way.
        let eo = PathOps.clip(
            subject: [outer, inner], subjectRule: .evenOdd, clip: [], op: .union)
        XCTAssertEqual(area(eo), 300, accuracy: 1e-3)
        XCTAssertEqual(eo.count, 2)
    }

    // MARK: - Flattening

    func testOpenPathRejected() {
        let open = RefinedPath(start: Pt(0, 0), segments: [.line(to: Pt(10, 0))], closed: false)
        XCTAssertThrowsError(try PathOps.rings(of: [open])) { error in
            XCTAssertEqual(error as? PathOpsError, .openSubpath(index: 0))
        }
    }

    func testFlattenCircleAreaWithinTolerance() throws {
        let node = ShapeNode(id: 0, kind: .circle(center: Pt(150, 150), r: 100))
        let rings = try PathOps.rings(of: Editing2.bakedPaths(of: node), tolerance: 0.25)
        XCTAssertEqual(rings.count, 1)
        let a = abs(Geometry.signedArea(rings[0]))
        let exact = Double.pi * 100 * 100
        // Chord flattening under-cuts by at most tolerance × perimeter.
        XCTAssertEqual(a, exact, accuracy: 0.006 * exact)
        // Coarser tolerance produces fewer vertices.
        let coarse = try PathOps.rings(of: Editing2.bakedPaths(of: node), tolerance: 2.0)
        XCTAssertLessThan(coarse[0].count, rings[0].count)
        XCTAssertGreaterThan(rings[0].count, 32)
    }

    // MARK: - Node-level combine

    func testCombineAdoptsFirstNodeStyle() {
        var a = rectNode(7, 0, 0, 10, 10)
        a.style.fill = .color(r: 200, g: 10, b: 10)
        a.attributes.svgID = "first"
        var b = rectNode(8, 5, 5, 10, 10)
        b.style.fill = .color(r: 10, g: 10, b: 200)
        guard let out = PathOps.combine([a, b], op: .union) else {
            return XCTFail("union of overlapping rects must not be nil")
        }
        XCTAssertEqual(out.id, 7)
        XCTAssertEqual(out.attributes.svgID, "first")
        XCTAssertEqual(out.style.fill, .color(r: 200, g: 10, b: 10))
        XCTAssertNil(out.transform)
        if case .keyword(let k)? = out.style.value(of: "fill-rule") {
            XCTAssertEqual(k, "evenodd")
        } else {
            XCTFail("combined node must declare fill-rule: evenodd")
        }
        guard case .path(let paths) = out.kind else { return XCTFail("kind must be .path") }
        let rings = try! PathOps.rings(of: paths)
        XCTAssertEqual(area(rings), 175, accuracy: 1e-3)
    }

    func testCombineSubtractCircleFromRect() {
        let rect = rectNode(0, 0, 0, 40, 40)
        let circle = ShapeNode(id: 1, kind: .circle(center: Pt(20, 20), r: 8))
        guard let out = PathOps.combine([rect, circle], op: .subtract) else {
            return XCTFail("subtract must produce a donut")
        }
        guard case .path(let paths) = out.kind else { return XCTFail() }
        XCTAssertEqual(paths.count, 2, "outer rect ring + circular hole")
        XCTAssertTrue(paths.allSatisfy { $0.closed })
        let rings = try! PathOps.rings(of: paths)
        let expected = 1600 - Double.pi * 64
        XCTAssertEqual(area(rings), expected, accuracy: 15)
    }

    func testCombineDisjointIntersectIsNil() {
        let a = rectNode(0, 0, 0, 10, 10)
        let b = rectNode(1, 30, 30, 10, 10)
        XCTAssertNil(PathOps.combine([a, b], op: .intersect))
    }

    func testCombineOpenPathIsNil() {
        let a = rectNode(0, 0, 0, 10, 10)
        let line = ShapeNode(id: 1, kind: .line(Pt(0, 0), Pt(10, 10)))
        XCTAssertNil(PathOps.combine([a, line], op: .union))
    }

    func testCombineSingleNodeNormalizesNonZero() {
        // Two nested same-orientation rings, no fill-rule declaration →
        // SVG default nonzero → solid; normalization emits the outer ring.
        let paths = [
            PathOps.ringPath(rectRing(0, 0, 20, 20)),
            PathOps.ringPath(rectRing(5, 5, 10, 10)),
        ]
        let node = ShapeNode(id: 0, kind: .path(paths))
        guard let out = PathOps.combine([node], op: .union) else { return XCTFail() }
        guard case .path(let outPaths) = out.kind else { return XCTFail() }
        let rings = try! PathOps.rings(of: outPaths)
        XCTAssertEqual(rings.count, 1)
        XCTAssertEqual(area(rings), 400, accuracy: 1e-3)
    }

    func testCombineTransformIsBaked() {
        var b = rectNode(1, 0, 0, 10, 10)
        b.transform = TransformValue(raw: "translate(5 5)", matrix: [1, 0, 0, 1, 5, 5])
        let a = rectNode(0, 0, 0, 10, 10)
        guard let out = PathOps.combine([a, b], op: .union) else { return XCTFail() }
        guard case .path(let paths) = out.kind else { return XCTFail() }
        let rings = try! PathOps.rings(of: paths)
        XCTAssertEqual(area(rings), 175, accuracy: 1e-3)
    }

    // MARK: - Simplify

    func testSimplifyMergesCollinearAndDropsDegenerate() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .line(to: Pt(5, 0)),
                .line(to: Pt(5, 0)),  // degenerate
                .line(to: Pt(10, 0)),  // collinear with previous run
                .line(to: Pt(10, 5)),
                .line(to: Pt(10, 10)),  // collinear
                .line(to: Pt(0, 10)),
                .line(to: Pt(0, 0)),  // explicit closing line → implicit
            ], closed: true)
        let node = ShapeNode(id: 0, kind: .path([rp]))
        let out = PathOps.simplifyNode(node)
        guard case .path(let paths) = out.kind else { return XCTFail() }
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths[0].closed)
        XCTAssertEqual(paths[0].start, Pt(0, 0))
        XCTAssertEqual(
            paths[0].segments,
            [.line(to: Pt(10, 0)), .line(to: Pt(10, 10)), .line(to: Pt(0, 10))])
    }

    func testSimplifyLeavesPrimitivesAndCurves() {
        let rect = rectNode(0, 0, 0, 10, 10)
        if case .rect = PathOps.simplifyNode(rect).kind {} else {
            XCTFail("primitives stay primitives")
        }
        let curve = RefinedPath(
            start: Pt(0, 0),
            segments: [.cubic(c1: Pt(3, -5), c2: Pt(7, -5), to: Pt(10, 0))], closed: false)
        let node = ShapeNode(id: 1, kind: .path([curve]))
        guard case .path(let paths) = PathOps.simplifyNode(node).kind else { return XCTFail() }
        XCTAssertEqual(paths[0].segments.count, 1)
    }

    // MARK: - Join

    func testJoinPathsConcatenatesMeetingEndpoints() {
        let a = ShapeNode(id: 0, kind: .polyline([Pt(0, 0), Pt(10, 0)]))
        let b = ShapeNode(id: 1, kind: .polyline([Pt(10, 0), Pt(10, 10)]))
        guard let out = PathOps.joinPaths(a, b, tolerance: 0.5) else { return XCTFail() }
        XCTAssertEqual(out.id, 0)
        guard case .path(let paths) = out.kind else { return XCTFail() }
        XCTAssertEqual(paths.count, 1)
        XCTAssertFalse(paths[0].closed)
        XCTAssertEqual(paths[0].start, Pt(0, 0))
        XCTAssertEqual(paths[0].segments.last?.endPoint, Pt(10, 10))
        XCTAssertEqual(paths[0].segments.count, 2, "no connector for an exact meet")
    }

    func testJoinPathsReversesAndCloses() {
        // b runs the "wrong way": its END meets a's end. Joining reverses it;
        // the resulting chain's own ends then meet within tolerance → closed.
        let a = ShapeNode(id: 0, kind: .polyline([Pt(0, 0), Pt(10, 0), Pt(10, 10)]))
        let b = ShapeNode(id: 1, kind: .polyline([Pt(0, 0.3), Pt(0, 10), Pt(10, 10)]))
        guard let out = PathOps.joinPaths(a, b, tolerance: 0.5) else { return XCTFail() }
        guard case .path(let paths) = out.kind else { return XCTFail() }
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths[0].closed, "chain whose ends meet within tolerance closes")
    }

    func testJoinPathsKeepsDistantChainsApart() {
        let a = ShapeNode(id: 0, kind: .polyline([Pt(0, 0), Pt(10, 0)]))
        let b = ShapeNode(id: 1, kind: .polyline([Pt(50, 50), Pt(60, 50)]))
        guard let out = PathOps.joinPaths(a, b, tolerance: 0.5) else { return XCTFail() }
        guard case .path(let paths) = out.kind else { return XCTFail() }
        XCTAssertEqual(paths.count, 2)
    }

    // MARK: - Determinism

    func testClipIsDeterministic() {
        var rng = LCG(state: 0xFEC7_0000_0001)
        let a = blob(&rng)
        let b = blob(&rng)
        let first = PathOps.clip(subject: [a], clip: [b], op: .exclude)
        let second = PathOps.clip(subject: [a], clip: [b], op: .exclude)
        XCTAssertEqual(first, second)
    }

    // MARK: - Render-based fuzz

    /// Deterministic seeded LCG (PCG-style multiplier) — no system entropy.
    struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
        mutating func double01() -> Double {
            Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        }
    }

    /// A blobby star-shaped 16-gon fully inside the 256² raster.
    func blob(_ rng: inout LCG) -> [Pt] {
        let cx = 90 + 76 * rng.double01()
        let cy = 90 + 76 * rng.double01()
        let base = 30 + 30 * rng.double01()
        var ring: [Pt] = []
        for i in 0..<16 {
            let ang = Double(i) / 16 * 2 * .pi
            let r = base * (0.6 + 0.8 * rng.double01())
            ring.append(Pt(cx + r * cos(ang), cy + r * sin(ang)))
        }
        return ring
    }

    static let fuzzSize = 256

    /// Fill rings into a hard-edged (no antialias) boolean mask.
    func mask(_ rings: [[Pt]], rule: FillRule = .evenOdd) -> [Bool] {
        let size = Self.fuzzSize
        var data = [UInt8](repeating: 0, count: size * size)
        data.withUnsafeMutableBytes { buf in
            guard
                let ctx = CGContext(
                    data: buf.baseAddress, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            ctx.setAllowsAntialiasing(false)
            ctx.setShouldAntialias(false)
            ctx.setFillColor(gray: 1, alpha: 1)
            let path = CGMutablePath()
            for ring in rings where ring.count >= 3 {
                path.move(to: CGPoint(x: ring[0].x, y: ring[0].y))
                for p in ring.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
                path.closeSubpath()
            }
            ctx.addPath(path)
            ctx.fillPath(using: rule == .evenOdd ? .evenOdd : .winding)
        }
        return data.map { $0 > 127 }
    }

    /// Pixels adjacent (8-neighbourhood) to a value transition: every pair of
    /// 8-adjacent differing pixels marks both ends (checking the E, S, SE and
    /// SW neighbour of each pixel covers all pairs once).
    func boundaryBand(_ m: [Bool]) -> [Bool] {
        let size = Self.fuzzSize
        var band = [Bool](repeating: false, count: m.count)
        m.withUnsafeBufferPointer { src in
            band.withUnsafeMutableBufferPointer { dst in
                for y in 0..<size {
                    let row = y * size
                    let south = y + 1 < size
                    for x in 0..<size {
                        let i = row + x
                        let v = src[i]
                        if x + 1 < size, src[i + 1] != v {
                            dst[i] = true
                            dst[i + 1] = true
                        }
                        if south {
                            if src[i + size] != v {
                                dst[i] = true
                                dst[i + size] = true
                            }
                            if x + 1 < size, src[i + size + 1] != v {
                                dst[i] = true
                                dst[i + size + 1] = true
                            }
                            if x > 0, src[i + size - 1] != v {
                                dst[i] = true
                                dst[i + size - 1] = true
                            }
                        }
                    }
                }
            }
        }
        return band
    }

    func pixelOp(_ op: BoolOp, _ a: Bool, _ b: Bool) -> Bool {
        switch op {
        case .union: return a || b
        case .subtract: return a && !b
        case .intersect: return a && b
        case .exclude: return a != b
        }
    }

    func testFuzzRasterAgreement() {
        var rng = LCG(state: 0x5EED_0000_F00D_0001)
        for pair in 0..<25 {
            let a = blob(&rng)
            let b = blob(&rng)
            let maskA = mask([a])
            let maskB = mask([b])
            for op in BoolOp.allCases {
                let result = PathOps.clip(subject: [a], clip: [b], op: op)
                let maskR = mask(result)
                var expected = [Bool](repeating: false, count: maskA.count)
                for i in expected.indices { expected[i] = pixelOp(op, maskA[i], maskB[i]) }
                let bandE = boundaryBand(expected)
                let bandR = boundaryBand(maskR)
                var compared = 0
                var agree = 0
                for i in expected.indices where !bandE[i] && !bandR[i] {
                    compared += 1
                    if expected[i] == maskR[i] { agree += 1 }
                }
                guard compared > 0 else { continue }
                let ratio = Double(agree) / Double(compared)
                XCTAssertGreaterThanOrEqual(
                    ratio, 0.99,
                    "pair \(pair) op \(op.rawValue): \(agree)/\(compared) off-band agreement")
            }
        }
    }
}
