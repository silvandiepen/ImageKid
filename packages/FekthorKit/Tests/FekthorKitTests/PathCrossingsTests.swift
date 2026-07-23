import XCTest

@testable import FekthorKit

final class PathCrossingsTests: XCTestCase {
    private func line(_ a: Pt, _ b: Pt) -> RefinedPath {
        RefinedPath(start: a, segments: [.line(to: b)], closed: false)
    }

    func testXCrossingFindsOnePointPerLine() {
        let a = line(Pt(0, 0), Pt(10, 10))
        let b = line(Pt(0, 10), Pt(10, 0))
        let hits = PathCrossings.crossings(of: a, with: [b])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].point.x, 5, accuracy: 0.01)
        XCTAssertEqual(hits[0].point.y, 5, accuracy: 0.01)
        XCTAssertEqual(hits[0].t, 0.5, accuracy: 0.01)
    }

    func testLineThroughCircleFindsTwoCrossings() {
        let horizontal = line(Pt(-20, 0), Pt(20, 0))
        let circle = Editing2.ellipsePath(center: Pt(0, 0), rx: 10, ry: 10)
        let hits = PathCrossings.crossings(of: horizontal, with: [circle])
        XCTAssertEqual(hits.count, 2)
        let xs = hits.map(\.point.x).sorted()
        XCTAssertEqual(xs[0], -10, accuracy: 0.15)
        XCTAssertEqual(xs[1], 10, accuracy: 0.15)
        XCTAssertEqual(hits[0].point.y, 0, accuracy: 0.15)
    }

    func testDisjointPathsHaveNoCrossings() {
        let a = line(Pt(0, 0), Pt(10, 0))
        let b = line(Pt(0, 5), Pt(10, 5))
        XCTAssertTrue(PathCrossings.crossings(of: a, with: [b]).isEmpty)
    }

    func testSharedEndpointIsNotACrossing() {
        let a = line(Pt(0, 0), Pt(10, 10))
        let b = line(Pt(10, 10), Pt(20, 0))
        XCTAssertTrue(PathCrossings.crossings(of: a, with: [b]).isEmpty)
    }

    func testInsertingCrossingsAddsAnchorsWithoutMovingGeometry() {
        let a = line(Pt(0, 0), Pt(10, 10))
        let cross1 = line(Pt(0, 6), Pt(10, 0))
        let cross2 = line(Pt(0, 10), Pt(10, 2))
        let inserted = PathCrossings.insertingCrossings(a, with: [cross1, cross2])
        // One segment became three: two new anchors.
        XCTAssertEqual(inserted.segments.count, 3)
        // Geometry unchanged: every new anchor still lies on y = x.
        var from = inserted.start
        for segment in inserted.segments {
            let end = segment.endPoint
            XCTAssertEqual(end.x, end.y, accuracy: 0.05)
            from = end
        }
        _ = from
        // End point intact.
        XCTAssertEqual(inserted.segments.last!.endPoint.x, 10, accuracy: 1e-6)
    }

    func testMultipleCrossingsInOneCubicSegmentRemapCorrectly() {
        // A shallow cubic crossed twice by two verticals.
        let curve = RefinedPath(
            start: Pt(0, 0),
            segments: [.cubic(c1: Pt(10, 0), c2: Pt(20, 0), to: Pt(30, 0))],
            closed: false)
        let v1 = line(Pt(8, -5), Pt(8, 5))
        let v2 = line(Pt(22, -5), Pt(22, 5))
        let inserted = PathCrossings.insertingCrossings(curve, with: [v1, v2])
        XCTAssertEqual(inserted.segments.count, 3)
        let anchors = inserted.segments.dropLast().map(\.endPoint)
        let xs = anchors.map(\.x).sorted()
        XCTAssertEqual(xs[0], 8, accuracy: 0.2)
        XCTAssertEqual(xs[1], 22, accuracy: 0.2)
    }
}
