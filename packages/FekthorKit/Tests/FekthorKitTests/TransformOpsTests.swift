import XCTest

@testable import FekthorKit

/// Geometry-baked transforms: skew (exact affine), 4-corner distort
/// (bilinear), pivot behaviour, primitive degrade rules, and composition
/// with a pre-existing `transform` attribute.
final class TransformOpsTests: XCTestCase {
    let rect = ShapeNode(
        id: 0, kind: .rect(x: 0, y: 0, width: 10, height: 10, rx: nil, ry: nil))

    /// The first subpath's start + segment endpoints (closing duplicate kept).
    func outlinePoints(_ node: ShapeNode) -> [Pt] {
        guard case .path(let paths) = node.kind, let rp = paths.first else { return [] }
        var out = [rp.start]
        for seg in rp.segments {
            switch seg {
            case .line(let to): out.append(to)
            case .cubic(_, _, let to): out.append(to)
            case .arc: break
            }
        }
        return out
    }

    func assertPt(_ p: Pt, _ q: Pt, accuracy: Double = 1e-9, line: UInt = #line) {
        XCTAssertEqual(p.x, q.x, accuracy: accuracy, line: line)
        XCTAssertEqual(p.y, q.y, accuracy: accuracy, line: line)
    }

    // MARK: Skew

    func testSkewRectIsParallelogram() {
        let out = TransformOps.skewed(rect, xDegrees: 45, yDegrees: 0, around: Pt(0, 0))
        guard case .path = out.kind else { return XCTFail("skew must bake to .path") }
        XCTAssertNil(out.transform)
        // (x, y) → (x + y·tan45, y) = (x + y, y): exact parallelogram corners.
        let pts = outlinePoints(out)
        assertPt(pts[0], Pt(0, 0))
        assertPt(pts[1], Pt(10, 0))
        assertPt(pts[2], Pt(20, 10))
        assertPt(pts[3], Pt(10, 10))
        // Pure shear has determinant 1: area preserved.
        XCTAssertEqual(Geometry.area(Array(pts[0..<4])), 100, accuracy: 1e-9)
    }

    func testSkewYPreservesAreaToo() {
        let out = TransformOps.skewed(rect, xDegrees: 0, yDegrees: 30, around: Pt(5, 5))
        let pts = outlinePoints(out)
        XCTAssertEqual(Geometry.area(Array(pts[0..<4])), 100, accuracy: 1e-9)
    }

    func testSkewPivotStaysPut() {
        // Skew about (0, 10): (x, y) → (x + (y − 10)·tan45, y).
        let out = TransformOps.skewed(rect, xDegrees: 45, yDegrees: 0, around: Pt(0, 10))
        let pts = outlinePoints(out)
        assertPt(pts[0], Pt(-10, 0))
        assertPt(pts[1], Pt(0, 0))
        assertPt(pts[2], Pt(10, 10))
        assertPt(pts[3], Pt(0, 10))  // on the pivot line: unmoved
        // Different pivot, different translation, same shape.
        let origin = TransformOps.skewed(rect, xDegrees: 45, yDegrees: 0, around: Pt(0, 0))
        let shifted = outlinePoints(origin)
        for (p, q) in zip(pts, shifted) {
            assertPt(Pt(p.x + 10, p.y), q)
        }
    }

    func testShearedIsAlias() {
        XCTAssertEqual(
            TransformOps.sheared(rect, xDegrees: 20, yDegrees: 5, around: Pt(3, 4)),
            TransformOps.skewed(rect, xDegrees: 20, yDegrees: 5, around: Pt(3, 4)))
    }

    // MARK: Distort

    func testDistortCornersLandExactly() {
        let targets = (tl: Pt(-1, -2), tr: Pt(12, 1), br: Pt(9, 14), bl: Pt(0, 11))
        let out = TransformOps.distorted(
            rect, corners: targets, from: (minX: 0, minY: 0, maxX: 10, maxY: 10))
        guard case .path = out.kind else { return XCTFail("distort must bake to .path") }
        let pts = outlinePoints(out)
        assertPt(pts[0], targets.tl)
        assertPt(pts[1], targets.tr)
        assertPt(pts[2], targets.br)
        assertPt(pts[3], targets.bl)
    }

    func testDistortMatchesSkewForAffineCorners() {
        // A bilinear warp whose corner targets come from an affine map IS
        // that affine map: distort == skew everywhere, corners included.
        let skewed = TransformOps.skewed(rect, xDegrees: 30, yDegrees: 10, around: Pt(0, 0))
        let sk = outlinePoints(skewed)
        let distorted = TransformOps.distorted(
            rect, corners: (tl: sk[0], tr: sk[1], br: sk[2], bl: sk[3]),
            from: (minX: 0, minY: 0, maxX: 10, maxY: 10))
        let di = outlinePoints(distorted)
        XCTAssertEqual(sk.count, di.count)
        for (p, q) in zip(sk, di) {
            assertPt(p, q, accuracy: 1e-9)
        }
    }

    func testDistortDegenerateBoundsIsNoOp() {
        let out = TransformOps.distorted(
            rect, corners: (tl: Pt(0, 0), tr: Pt(1, 0), br: Pt(1, 1), bl: Pt(0, 1)),
            from: (minX: 3, minY: 3, maxX: 3, maxY: 9))
        XCTAssertEqual(out, rect)
    }

    // MARK: Degrade rules

    func testPrimitivesDegradeToPath() {
        let circle = ShapeNode(id: 1, kind: .circle(center: Pt(5, 5), r: 5))
        guard
            case .path = TransformOps.skewed(
                circle, xDegrees: 15, yDegrees: 0, around: Pt(5, 5)
            ).kind
        else { return XCTFail("skewed circle must be .path") }
        guard
            case .path = TransformOps.distorted(
                circle, corners: (tl: Pt(0, 0), tr: Pt(10, 2), br: Pt(10, 10), bl: Pt(0, 8)),
                from: (minX: 0, minY: 0, maxX: 10, maxY: 10)
            ).kind
        else { return XCTFail("distorted circle must be .path") }
    }

    func testExistingTransformBakesFirst() {
        var moved = rect
        moved.transform = TransformValue(raw: "translate(5)", matrix: [1, 0, 0, 1, 5, 0])
        let out = TransformOps.skewed(moved, xDegrees: 45, yDegrees: 0, around: Pt(0, 0))
        XCTAssertNil(out.transform)
        // translate first: x ∈ [5, 15]; then shear: (x + y, y).
        let pts = outlinePoints(out)
        assertPt(pts[0], Pt(5, 0))
        assertPt(pts[1], Pt(15, 0))
        assertPt(pts[2], Pt(25, 10))
        assertPt(pts[3], Pt(15, 10))
    }

    // MARK: Numeric wrappers

    func testNumericWrappersDelegate() {
        XCTAssertEqual(
            TransformOps.scaledNumeric(rect, sx: 2, sy: 0.5, around: Pt(5, 5)),
            Editing2.scaled(rect, sx: 2, sy: 0.5, around: Pt(5, 5)))
        XCTAssertEqual(
            TransformOps.rotatedNumeric(rect, degrees: 90, around: Pt(5, 5)),
            Editing2.rotated(rect, by: .pi / 2, around: Pt(5, 5)))
    }
}
