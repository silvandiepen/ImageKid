import XCTest

@testable import FekthorKit

final class CornerRadiusTests: XCTestCase {
    /// Shoelace area of the flattened outline (closed).
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

    private func bounds(of path: RefinedPath) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let pts = PathRefine.flatten(path)
        return (
            pts.map(\.x).min() ?? 0, pts.map(\.y).min() ?? 0,
            pts.map(\.x).max() ?? 0, pts.map(\.y).max() ?? 0
        )
    }

    func testUniformRadiiMatchRectPathify() {
        let built = CornerRadius.roundedRectPath(
            x: 4, y: 6, width: 100, height: 60,
            topLeft: 10, topRight: 10, bottomRight: 10, bottomLeft: 10)
        let native = Editing2.pathify(
            .rect(x: 4, y: 6, width: 100, height: 60, rx: 10, ry: 10))[0]
        // Same construction — identical structure…
        XCTAssertEqual(built, native)
        // …and identical sampled outlines (belt and braces).
        let a = PathRefine.flatten(built)
        let b = PathRefine.flatten(native)
        XCTAssertEqual(a.count, b.count)
        for (pa, pb) in zip(a, b) {
            XCTAssertEqual(pa.x, pb.x, accuracy: 1e-12)
            XCTAssertEqual(pa.y, pb.y, accuracy: 1e-12)
        }
    }

    func testPerCornerBoundsAndArea() {
        let p = CornerRadius.roundedRectPath(
            x: 0, y: 0, width: 80, height: 40,
            topLeft: 20, topRight: 0, bottomRight: 8, bottomLeft: 4)
        // Rounding never leaves the rect: bounds are the rect itself (the
        // sharp top-right corner pins maxX/minY exactly).
        let b = bounds(of: p)
        XCTAssertEqual(b.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(b.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(b.maxX, 80, accuracy: 1e-9)
        XCTAssertEqual(b.maxY, 40, accuracy: 1e-9)
        // Each rounded corner removes (1 − π/4)·r² from the full rect (the
        // kappa cubic tracks a quarter circle to well under the tolerance).
        let radiusSquares: Double = 20.0 * 20.0 + 8.0 * 8.0 + 4.0 * 4.0
        let expected: Double = 80.0 * 40.0 - (1.0 - Double.pi / 4.0) * radiusSquares
        // Tolerance covers the flattening chords (the polygon sits just
        // inside the true rounds).
        XCTAssertEqual(area(of: p), expected, accuracy: 2.5)
    }

    func testAdjacentRadiiClampProportionally() {
        // The top side asks for 200 + 200 on an 80-wide rect → every radius
        // scales by 80/400 = 0.2 (CSS proportional reduction), so the
        // corners keep their relative weights.
        let (tl, tr, br, bl) = CornerRadius.clamped(
            width: 80, height: 100, topLeft: 200, topRight: 200, bottomRight: 40, bottomLeft: 0)
        XCTAssertEqual(tl, 40, accuracy: 1e-9)
        XCTAssertEqual(tr, 40, accuracy: 1e-9)
        XCTAssertEqual(br, 8, accuracy: 1e-9)
        XCTAssertEqual(bl, 0, accuracy: 1e-9)
        // The built path reflects the clamp (start = top-left corner end)
        // and still stays inside the rect.
        let p = CornerRadius.roundedRectPath(
            x: 0, y: 0, width: 80, height: 100,
            topLeft: 200, topRight: 200, bottomRight: 40, bottomLeft: 0)
        XCTAssertEqual(p.start, Pt(40, 0))
        let b = bounds(of: p)
        XCTAssertGreaterThanOrEqual(b.minX, -1e-9)
        XCTAssertLessThanOrEqual(b.maxX, 80 + 1e-9)
        XCTAssertLessThanOrEqual(b.maxY, 100 + 1e-9)
        // Negative radii floor at zero (sharp corner).
        let q = CornerRadius.clamped(
            width: 80, height: 100, topLeft: -5, topRight: 10, bottomRight: 10, bottomLeft: 10)
        XCTAssertEqual(q.tl, 0)
    }

    func testZeroRadiiIsSharpRect() {
        let built = CornerRadius.roundedRectPath(
            x: 2, y: 3, width: 50, height: 30,
            topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
        let native = Editing2.pathify(
            .rect(x: 2, y: 3, width: 50, height: 30, rx: nil, ry: nil))[0]
        XCTAssertEqual(built, native)
        XCTAssertEqual(built.segments.count, 4)  // four lines, no cubics
        XCTAssertTrue(built.closed)
    }
}
