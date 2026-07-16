import CoreGraphics
import XCTest
@testable import ImageKid

final class PixelSamplerTests: XCTestCase {
    func testTopMapsToFirstBitmapRow() {
        let coordinates = PixelSampler.pixelCoordinates(
            normalizedPoint: CGPoint(x: 0.5, y: 0),
            width: 100,
            height: 200
        )

        XCTAssertEqual(coordinates.x, 50)
        XCTAssertEqual(coordinates.y, 0)
    }

    func testBottomMapsToLastBitmapRow() {
        let coordinates = PixelSampler.pixelCoordinates(
            normalizedPoint: CGPoint(x: 0.5, y: 0.999),
            width: 100,
            height: 200
        )

        XCTAssertEqual(coordinates.x, 50)
        XCTAssertEqual(coordinates.y, 199)
    }

    func testCoordinatesAreClamped() {
        let coordinates = PixelSampler.pixelCoordinates(
            normalizedPoint: CGPoint(x: 2, y: -1),
            width: 10,
            height: 20
        )

        XCTAssertEqual(coordinates.x, 9)
        XCTAssertEqual(coordinates.y, 0)
    }
}
