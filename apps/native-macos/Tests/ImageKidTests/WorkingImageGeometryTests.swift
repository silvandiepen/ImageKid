import CoreGraphics
import XCTest
@testable import ImageKid

final class WorkingImageGeometryTests: XCTestCase {
    func testDisplayPointMapsIntoAppliedCrop() {
        let crop = CGRect(x: 0.25, y: 0.20, width: 0.50, height: 0.40)
        let result = WorkingImageGeometry.sourcePoint(
            fromDisplayNormalized: CGPoint(x: 0.5, y: 0.5),
            cropRect: crop
        )

        XCTAssertEqual(result.x, 0.50, accuracy: 0.0001)
        XCTAssertEqual(result.y, 0.40, accuracy: 0.0001)
    }

    func testSourceRectRoundTripsThroughDisplayCrop() throws {
        let crop = CGRect(x: 0.20, y: 0.10, width: 0.60, height: 0.70)
        let source = CGRect(x: 0.32, y: 0.24, width: 0.18, height: 0.21)

        let display = try XCTUnwrap(
            WorkingImageGeometry.displayRect(fromSourceNormalized: source, cropRect: crop)
        )
        let roundTrip = WorkingImageGeometry.sourceRect(
            fromDisplayNormalized: display,
            cropRect: crop
        )

        XCTAssertEqual(roundTrip.minX, source.minX, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.minY, source.minY, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.width, source.width, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.height, source.height, accuracy: 0.0001)
    }

    func testFreehandBuilderAlwaysRecordsStartAndEnd() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        let start = CGPoint(x: 20, y: 30)
        let end = CGPoint(x: 120, y: 160)

        let points = FreehandStrokeBuilder.append(
            points: [],
            start: start,
            location: end,
            inside: bounds
        )

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].x, start.x)
        XCTAssertEqual(points[0].y, start.y)
        XCTAssertEqual(points[1].x, end.x)
        XCTAssertEqual(points[1].y, end.y)
    }

    func testCroppedPixelSizeReflectsAppliedCrop() {
        let result = WorkingImageGeometry.croppedPixelSize(
            sourceSize: CGSize(width: 2000, height: 1000),
            cropRect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25)
        )

        XCTAssertEqual(result.width, 1000)
        XCTAssertEqual(result.height, 250)
    }
}
