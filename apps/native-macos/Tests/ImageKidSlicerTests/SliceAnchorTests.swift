import CoreGraphics
import XCTest
@testable import ImageKidSlicer

/// The typed size and position the slice inspector writes.
final class SliceAnchorTests: XCTestCase {
    private let pixelSize = CGSize(width: 400, height: 200)

    func testTopLeftAnchorKeepsTheTopLeftCornerPut() {
        let rect = CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25)
        let resized = SliceGeometry.resized(
            rect,
            toPixelSize: CGSize(width: 40, height: 20),
            anchor: .topLeft,
            pixelSize: pixelSize
        )
        XCTAssertEqual(resized.minX, 0.25, accuracy: 0.0001)
        XCTAssertEqual(resized.minY, 0.25, accuracy: 0.0001)
        XCTAssertEqual(resized.width * pixelSize.width, 40, accuracy: 0.001)
        XCTAssertEqual(resized.height * pixelSize.height, 20, accuracy: 0.001)
    }

    func testCentreAnchorGrowsInEveryDirection() {
        let rect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let resized = SliceGeometry.resized(
            rect,
            toPixelSize: CGSize(width: 160, height: 80),
            anchor: .centre,
            pixelSize: pixelSize
        )
        XCTAssertEqual(resized.midX, rect.midX, accuracy: 0.0001)
        XCTAssertEqual(resized.midY, rect.midY, accuracy: 0.0001)
        XCTAssertEqual(resized.width, 0.4, accuracy: 0.0001)
    }

    func testBottomRightAnchorKeepsTheFarCornerPut() {
        let rect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let resized = SliceGeometry.resized(
            rect,
            toPixelSize: CGSize(width: 40, height: 20),
            anchor: .bottomRight,
            pixelSize: pixelSize
        )
        XCTAssertEqual(resized.maxX, rect.maxX, accuracy: 0.0001)
        XCTAssertEqual(resized.maxY, rect.maxY, accuracy: 0.0001)
    }

    func testAnEdgeAnchorOnlyHoldsItsOwnAxis() {
        let rect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let resized = SliceGeometry.resized(
            rect,
            toPixelSize: CGSize(width: 40, height: 60),
            anchor: .top,
            pixelSize: pixelSize
        )
        XCTAssertEqual(resized.minY, rect.minY, accuracy: 0.0001, "the top edge is held")
        XCTAssertEqual(resized.midX, rect.midX, accuracy: 0.0001, "and it centres horizontally")
    }

    func testResizingStaysInsideTheSource() {
        let rect = CGRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1)
        let resized = SliceGeometry.resized(
            rect,
            toPixelSize: CGSize(width: 4000, height: 2000),
            anchor: .topLeft,
            pixelSize: pixelSize
        )
        XCTAssertEqual(resized, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testAZeroSizeIsRaisedToOnePixel() {
        let resized = SliceGeometry.resized(
            CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
            toPixelSize: .zero,
            anchor: .topLeft,
            pixelSize: pixelSize
        )
        XCTAssertEqual(resized.width * pixelSize.width, 1, accuracy: 0.001)
        XCTAssertEqual(resized.height * pixelSize.height, 1, accuracy: 0.001)
    }

    func testMovingToAPixelOriginKeepsTheSize() {
        let rect = CGRect(x: 0.1, y: 0.1, width: 0.25, height: 0.25)
        let moved = SliceGeometry.moved(
            rect,
            toPixelOrigin: CGPoint(x: 200, y: 100),
            pixelSize: pixelSize
        )
        XCTAssertEqual(moved.minX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(moved.minY, 0.5, accuracy: 0.0001)
        XCTAssertEqual(moved.size, rect.size)
    }

    func testMovingPastTheEdgeStopsWithoutShrinking() {
        let rect = CGRect(x: 0.1, y: 0.1, width: 0.25, height: 0.25)
        let moved = SliceGeometry.moved(
            rect,
            toPixelOrigin: CGPoint(x: 9999, y: 9999),
            pixelSize: pixelSize
        )
        XCTAssertEqual(moved.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(moved.size, rect.size)
    }

    func testEveryAnchorHasADistinctPointAndLabel() {
        XCTAssertEqual(Set(SliceAnchor.allCases.map(\.label)).count, SliceAnchor.allCases.count)
        XCTAssertEqual(
            Set(SliceAnchor.allCases.map { "\($0.unitPoint.x),\($0.unitPoint.y)" }).count,
            SliceAnchor.allCases.count
        )
    }
}
