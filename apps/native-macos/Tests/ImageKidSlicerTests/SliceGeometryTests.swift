import CoreGraphics
import XCTest
@testable import ImageKidSlicer

final class SliceGeometryTests: XCTestCase {
    private let pixelSize = CGSize(width: 400, height: 200)

    // MARK: - Creation

    func testRectFromDragIsOrderIndependent() {
        let forward = SliceGeometry.rect(from: CGPoint(x: 0.2, y: 0.3), to: CGPoint(x: 0.6, y: 0.8))
        let backward = SliceGeometry.rect(from: CGPoint(x: 0.6, y: 0.8), to: CGPoint(x: 0.2, y: 0.3))
        XCTAssertEqual(forward.minX, backward.minX, accuracy: 0.0001)
        XCTAssertEqual(forward.minY, backward.minY, accuracy: 0.0001)
        XCTAssertEqual(forward.width, backward.width, accuracy: 0.0001)
        XCTAssertEqual(forward.height, backward.height, accuracy: 0.0001)
        XCTAssertEqual(forward.minX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(forward.width, 0.4, accuracy: 0.0001)
    }

    func testSquareDragIsSquareInPixelsNotInNormalisedUnits() {
        // 400×200 source: a pixel-square region is twice as tall as it is wide
        // in normalised space.
        let rect = SliceGeometry.rect(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 0.25, y: 0.1),
            square: true,
            pixelAspect: pixelSize.width / pixelSize.height
        )
        XCTAssertEqual(rect.width * pixelSize.width, rect.height * pixelSize.height, accuracy: 0.001)
    }

    func testTinyDragIsNotMeaningful() {
        let rect = SliceGeometry.rect(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.501, y: 0.501))
        XCTAssertFalse(SliceGeometry.isMeaningful(rect))
        XCTAssertTrue(SliceGeometry.isMeaningful(CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)))
    }

    // MARK: - Clamping

    func testClampingAtEveryEdge() {
        XCTAssertEqual(
            SliceGeometry.clamped(CGRect(x: -0.5, y: 0.1, width: 0.3, height: 0.3)),
            CGRect(x: 0, y: 0.1, width: 0.3, height: 0.3)
        )
        XCTAssertEqual(
            SliceGeometry.clamped(CGRect(x: 0.1, y: -0.5, width: 0.3, height: 0.3)),
            CGRect(x: 0.1, y: 0, width: 0.3, height: 0.3)
        )
        XCTAssertEqual(
            SliceGeometry.clamped(CGRect(x: 0.9, y: 0.1, width: 0.3, height: 0.3)),
            CGRect(x: 0.7, y: 0.1, width: 0.3, height: 0.3)
        )
        XCTAssertEqual(
            SliceGeometry.clamped(CGRect(x: 0.1, y: 0.9, width: 0.3, height: 0.3)),
            CGRect(x: 0.1, y: 0.7, width: 0.3, height: 0.3)
        )
    }

    func testClampingTrimsARectangleLargerThanTheSource() {
        let rect = SliceGeometry.clamped(CGRect(x: -0.2, y: -0.2, width: 2, height: 2))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testNonFiniteRectangleCollapsesRatherThanPropagating() {
        XCTAssertEqual(SliceGeometry.clamped(CGRect(x: .nan, y: 0, width: 0.2, height: 0.2)), .zero)
    }

    // MARK: - Moving and resizing

    func testMoveStopsAtTheEdgeWithoutShrinking() {
        let start = CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.2)
        let moved = SliceGeometry.moved(start, by: CGSize(width: 0.5, height: 0.5))
        XCTAssertEqual(moved, CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2))
    }

    func testResizeAllowsEdgesToCross() {
        let start = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let flipped = SliceGeometry.resized(start, handle: .left, to: CGPoint(x: 0.9, y: 0.5))
        XCTAssertEqual(flipped.minX, 0.6, accuracy: 0.0001)
        XCTAssertEqual(flipped.maxX, 0.9, accuracy: 0.0001)
    }

    func testResizeStaysInsideTheSource() {
        let start = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let resized = SliceGeometry.resized(start, handle: .bottomRight, to: CGPoint(x: 1.6, y: 1.6))
        XCTAssertEqual(resized.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(resized.maxY, 1, accuracy: 0.0001)
    }

    func testSquareCornerResizeKeepsTheOppositeCornerPut() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)
        let resized = SliceGeometry.resized(
            start,
            handle: .bottomRight,
            to: CGPoint(x: 0.5, y: 0.4),
            square: true,
            pixelAspect: pixelSize.width / pixelSize.height
        )
        XCTAssertEqual(resized.minX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(resized.minY, 0.2, accuracy: 0.0001)
        XCTAssertEqual(resized.width * pixelSize.width, resized.height * pixelSize.height, accuracy: 0.001)
    }

    func testDuplicateOffsetsWithoutLeavingTheSource() {
        let edge = CGRect(x: 0.95, y: 0.95, width: 0.05, height: 0.05)
        let copy = SliceGeometry.duplicated(edge)
        XCTAssertEqual(copy, edge, "A slice already at the corner has nowhere to go and must stay valid")
    }

    // MARK: - Pixel resolution

    func testPixelRectRoundsToWholePixels() {
        let rect = SliceGeometry.pixelRect(
            CGRect(x: 0.1001, y: 0.2002, width: 0.25, height: 0.25),
            pixelSize: pixelSize
        )
        XCTAssertEqual(rect, CGRect(x: 40, y: 40, width: 100, height: 50))
    }

    func testPixelRectSpansTheWholeSourceWhenNormalised() {
        let rect = SliceGeometry.pixelRect(CGRect(x: 0, y: 0, width: 1, height: 1), pixelSize: pixelSize)
        XCTAssertEqual(rect, CGRect(origin: .zero, size: pixelSize))
    }

    func testPixelRectNeverExceedsTheSource() {
        let rect = SliceGeometry.pixelRect(CGRect(x: 0.99, y: 0.99, width: 0.5, height: 0.5), pixelSize: pixelSize)
        XCTAssertNotNil(rect)
        XCTAssertLessThanOrEqual(rect!.maxX, pixelSize.width)
        XCTAssertLessThanOrEqual(rect!.maxY, pixelSize.height)
    }

    func testSubPixelSliceStillProducesOnePixel() {
        let rect = SliceGeometry.pixelRect(
            CGRect(x: 0.5, y: 0.5, width: 0.0001, height: 0.0001),
            pixelSize: pixelSize
        )
        XCTAssertEqual(rect?.width, 1)
        XCTAssertEqual(rect?.height, 1)
    }

    func testEmptySliceIsRejected() {
        XCTAssertNil(SliceGeometry.pixelRect(CGRect(x: 0.5, y: 0.5, width: 0, height: 0.2), pixelSize: pixelSize))
        XCTAssertNil(SliceGeometry.pixelRect(CGRect(x: 0, y: 0, width: 1, height: 1), pixelSize: .zero))
    }
}
