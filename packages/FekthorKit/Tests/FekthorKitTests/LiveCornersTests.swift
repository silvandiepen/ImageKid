import XCTest

@testable import FekthorKit

final class LiveCornersTests: XCTestCase {
    // MARK: - Helpers

    private func area(of path: RefinedPath) -> Double {
        let pts = PathRefine.flatten(path)
        guard pts.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<pts.count {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    private func bounds(of path: RefinedPath)
        -> (minX: Double, minY: Double, maxX: Double, maxY: Double)
    {
        let pts = PathRefine.flatten(path)
        return (
            pts.map(\.x).min() ?? 0, pts.map(\.y).min() ?? 0,
            pts.map(\.x).max() ?? 0, pts.map(\.y).max() ?? 0
        )
    }

    private func square(_ s: Double = 100) -> RefinedPath {
        RefinedPath(
            start: Pt(0, 0),
            segments: [
                .line(to: Pt(s, 0)), .line(to: Pt(s, s)), .line(to: Pt(0, s)),
                .line(to: Pt(0, 0)),
            ], closed: true)
    }

    private func triangle() -> RefinedPath {
        // Implicit closure (polygon pathify style: no explicit closing line).
        RefinedPath(
            start: Pt(0, 0), segments: [.line(to: Pt(80, 0)), .line(to: Pt(40, 60))],
            closed: true)
    }

    // MARK: - Corner detection

    func testSquareHasFourCorners() {
        let corners = LiveCorners.cornerAnchors(of: square())
        XCTAssertEqual(corners.map(\.index), [0, 1, 2, 3])
        for c in corners {
            XCTAssertEqual(c.turnAngle, .pi / 2, accuracy: 1e-9)
        }
        // Bisectors point INTO the square (dot at 0,0 offsets toward +x,+y).
        let seam = corners[0]
        XCTAssertGreaterThan(seam.bisector.x, 0)
        XCTAssertGreaterThan(seam.bisector.y, 0)
    }

    func testTriangleImplicitClosureHasThreeCorners() {
        let corners = LiveCorners.cornerAnchors(of: triangle())
        XCTAssertEqual(corners.map(\.index), [0, 1, 2])
    }

    func testNearCollinearAnchorIsNotACorner() {
        // A 5° bend on an open polyline: below the 15° threshold.
        let end = Pt(100, 50 * tan(5 * Double.pi / 180))
        let path = RefinedPath(
            start: Pt(0, 0), segments: [.line(to: Pt(50, 0)), .line(to: end)], closed: false)
        XCTAssertTrue(LiveCorners.cornerAnchors(of: path).isEmpty)
        // …and rounding leaves the path untouched.
        XCTAssertEqual(LiveCorners.rounded(path: path, radius: 10), path)
    }

    func testOpenPathEndpointsAreNeverCorners() {
        let path = RefinedPath(
            start: Pt(0, 0), segments: [.line(to: Pt(50, 0)), .line(to: Pt(50, 50))],
            closed: false)
        XCTAssertEqual(LiveCorners.cornerAnchors(of: path).map(\.index), [1])
    }

    func testCurveAdjacentAnchorIsSkipped() {
        // line → cubic joint: not a line-line corner in v1.
        let path = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .line(to: Pt(50, 0)),
                .cubic(c1: Pt(70, 0), c2: Pt(80, 20), to: Pt(80, 40)),
                .line(to: Pt(0, 40)),
            ], closed: false)
        XCTAssertTrue(LiveCorners.cornerAnchors(of: path).isEmpty)
    }

    // MARK: - Fillets

    func testSquareAllCornersMatchesNativeRoundedRect() {
        let rounded = LiveCorners.rounded(path: square(), radius: 10)
        // Same area as the kappa-cubic rounded rect the rect path builds.
        let native = Editing2.pathify(
            .rect(x: 0, y: 0, width: 100, height: 100, rx: 10, ry: 10))[0]
        XCTAssertEqual(area(of: rounded), area(of: native), accuracy: 0.5)
        // Bounds unchanged; area strictly below the sharp square's.
        let b = bounds(of: rounded)
        XCTAssertEqual(b.minX, 0, accuracy: 1e-6)
        XCTAssertEqual(b.minY, 0, accuracy: 1e-6)
        XCTAssertEqual(b.maxX, 100, accuracy: 1e-6)
        XCTAssertEqual(b.maxY, 100, accuracy: 1e-6)
        XCTAssertLessThan(area(of: rounded), 100 * 100)
    }

    func testTriangleFilletAreaAndBounds() {
        let sharp = triangle()
        let rounded = LiveCorners.rounded(path: sharp, radius: 6)
        XCTAssertLessThan(area(of: rounded), area(of: sharp))
        // Fillets stay inside the sharp outline.
        let sb = bounds(of: sharp)
        let rb = bounds(of: rounded)
        XCTAssertGreaterThanOrEqual(rb.minX, sb.minX - 1e-6)
        XCTAssertGreaterThanOrEqual(rb.minY, sb.minY - 1e-6)
        XCTAssertLessThanOrEqual(rb.maxX, sb.maxX + 1e-6)
        XCTAssertLessThanOrEqual(rb.maxY, sb.maxY + 1e-6)
        // Three fillets: three cubics among the segments.
        let cubics = rounded.segments.filter {
            if case .cubic = $0 { return true } else { return false }
        }
        XCTAssertEqual(cubics.count, 3)
    }

    /// Tangency: each fillet cubic leaves its entry point along the incoming
    /// edge direction and arrives along the outgoing edge direction.
    func testFilletTangency() {
        let rounded = LiveCorners.rounded(path: square(), radius: 12, corners: [1])
        // Corner 1 = (100, 0): incoming edge +x, outgoing edge +y.
        var found = false
        var current = rounded.start
        for seg in rounded.segments {
            if case .cubic(let c1, let c2, let to) = seg {
                found = true
                // Entry tangent ~ +x.
                XCTAssertEqual(c1.y - current.y, 0, accuracy: 1e-9)
                XCTAssertGreaterThan(c1.x - current.x, 0)
                // Exit tangent ~ +y.
                XCTAssertEqual(to.x - c2.x, 0, accuracy: 1e-9)
                XCTAssertGreaterThan(to.y - c2.y, 0)
                // Tangency points sit ON the edges, 12 units from the corner.
                XCTAssertEqual(current.x, 88, accuracy: 1e-9)
                XCTAssertEqual(current.y, 0, accuracy: 1e-9)
                XCTAssertEqual(to.x, 100, accuracy: 1e-9)
                XCTAssertEqual(to.y, 12, accuracy: 1e-9)
            }
            current = seg.endPoint
        }
        XCTAssertTrue(found)
    }

    func testClampToHalfShorterAdjacentSegment() {
        // Radius 80 on a 100-square: right-angle trim t = r, clamped to 50.
        let rounded = LiveCorners.rounded(path: square(), radius: 80, corners: [1])
        var entry: Pt? = nil
        var exit: Pt? = nil
        var current = rounded.start
        for seg in rounded.segments {
            if case .cubic(_, _, let to) = seg {
                entry = current
                exit = to
            }
            current = seg.endPoint
        }
        XCTAssertEqual(entry?.x ?? 0, 50, accuracy: 1e-9)  // half the top edge
        XCTAssertEqual(exit?.y ?? 0, 50, accuracy: 1e-9)  // half the right edge
    }

    func testSubsetOfCornersOnlyTouchesThose() {
        let rounded = LiveCorners.rounded(path: square(), radius: 10, corners: [2])
        let cubics = rounded.segments.filter {
            if case .cubic = $0 { return true } else { return false }
        }
        XCTAssertEqual(cubics.count, 1)
        // The other three corner points survive verbatim.
        let pts = PathRefine.flatten(rounded)
        func hasPoint(_ p: Pt) -> Bool {
            pts.contains { abs($0.x - p.x) < 1e-6 && abs($0.y - p.y) < 1e-6 }
        }
        XCTAssertTrue(hasPoint(Pt(0, 0)))
        XCTAssertTrue(hasPoint(Pt(100, 0)))
        XCTAssertTrue(hasPoint(Pt(0, 100)))
        XCTAssertFalse(hasPoint(Pt(100, 100)))
    }

    func testClosedSeamCornerRounds() {
        let rounded = LiveCorners.rounded(path: square(), radius: 10, corners: [0])
        // The start moved onto the fillet's exit (10 down the left→top edge).
        XCTAssertEqual(rounded.start.x, 10, accuracy: 1e-9)
        XCTAssertEqual(rounded.start.y, 0, accuracy: 1e-9)
        XCTAssertTrue(rounded.closed)
        // Outline closes: the last segment lands on the start.
        XCTAssertEqual(rounded.segments.last?.endPoint.x ?? -1, 10, accuracy: 1e-9)
        XCTAssertEqual(rounded.segments.last?.endPoint.y ?? -1, 0, accuracy: 1e-9)
        XCTAssertLessThan(area(of: rounded), 100 * 100)
    }

    func testZeroRadiusIsIdentity() {
        XCTAssertEqual(LiveCorners.rounded(path: square(), radius: 0), square())
    }

    func testPolygonPentagonRoundsAllCorners() {
        var pts: [Pt] = []
        for i in 0..<5 {
            let a = Double(i) * 2 * .pi / 5 - .pi / 2
            pts.append(Pt(50 + 40 * cos(a), 50 + 40 * sin(a)))
        }
        let path = Editing2.pathify(.polygon(pts))[0]
        let rounded = LiveCorners.rounded(path: path, radius: 5)
        let cubics = rounded.segments.filter {
            if case .cubic = $0 { return true } else { return false }
        }
        XCTAssertEqual(cubics.count, 5)
        XCTAssertLessThan(area(of: rounded), area(of: path))
    }
}
