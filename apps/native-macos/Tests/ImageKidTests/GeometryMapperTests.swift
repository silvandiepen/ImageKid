import CoreGraphics
import XCTest
@testable import ImageKid

final class GeometryMapperTests: XCTestCase {
    func testAspectFitCentersLandscapeContent() {
        let result = GeometryMapper.aspectFitRect(
            contentSize: CGSize(width: 200, height: 100),
            in: CGRect(x: 0, y: 0, width: 300, height: 300)
        )

        XCTAssertEqual(result, CGRect(x: 0, y: 75, width: 300, height: 150))
    }

    func testNormalizedPoint() {
        let result = GeometryMapper.normalizedPoint(
            CGPoint(x: 150, y: 100),
            in: CGRect(x: 50, y: 50, width: 200, height: 100)
        )

        XCTAssertEqual(result?.x, 0.5)
        XCTAssertEqual(result?.y, 0.5)
    }

    func testPointOutsideImageReturnsNil() {
        XCTAssertNil(
            GeometryMapper.normalizedPoint(
                CGPoint(x: 0, y: 0),
                in: CGRect(x: 10, y: 10, width: 100, height: 100)
            )
        )
    }
}
