import CoreGraphics
import XCTest

@testable import BrushKit

final class StrokeInputTests: XCTestCase {

    func testArcLengthOfAStraightLine() {
        let input = StrokeInput(samples: [
            StrokeSample(position: CGPoint(x: 0, y: 0)),
            StrokeSample(position: CGPoint(x: 30, y: 40)),  // 3-4-5 → 50
        ])
        XCTAssertEqual(input.arcLength, 50, accuracy: 1e-9)
    }

    func testDerivedVelocityFromTimestamps() {
        let input = StrokeInput(samples: [
            StrokeSample(position: CGPoint(x: 0, y: 0), timestamp: 0),
            StrokeSample(position: CGPoint(x: 100, y: 0), timestamp: 0.5),  // 200 pt/s
        ]).withDerivedVelocity()
        XCTAssertEqual(input.samples[1].velocity, 200, accuracy: 1e-6)
    }

    func testSampleAtArcLengthInterpolates() {
        let input = StrokeInput(samples: [
            StrokeSample(position: CGPoint(x: 0, y: 0), pressure: 0),
            StrokeSample(position: CGPoint(x: 100, y: 0), pressure: 1),
        ])
        let mid = input.sample(atArcLength: 50)
        XCTAssertEqual(mid?.position.x ?? 0, 50, accuracy: 1e-6)
        XCTAssertEqual(mid?.pressure ?? 0, 0.5, accuracy: 1e-6)
    }

    func testSmoothingPinsEndpointsAndPullsInteriorIn() {
        // A spike in the middle; smoothing should pull it toward the line but
        // leave the endpoints exactly where they were.
        let input = StrokeInput(samples: [
            StrokeSample(position: CGPoint(x: 0, y: 0)),
            StrokeSample(position: CGPoint(x: 50, y: 100)),
            StrokeSample(position: CGPoint(x: 100, y: 0)),
        ])
        let out = input.smoothed(amount: 1)
        XCTAssertEqual(out.samples.first!.position, CGPoint(x: 0, y: 0))
        XCTAssertEqual(out.samples.last!.position, CGPoint(x: 100, y: 0))
        // The spike (y=100) is averaged toward its neighbours' midpoint (y=0).
        XCTAssertLessThan(out.samples[1].position.y, 100)
    }

    func testSmoothingZeroIsIdentity() {
        let input = StrokeInput(samples: [
            StrokeSample(position: CGPoint(x: 0, y: 0)),
            StrokeSample(position: CGPoint(x: 50, y: 100)),
            StrokeSample(position: CGPoint(x: 100, y: 0)),
        ])
        XCTAssertEqual(input.smoothed(amount: 0), input)
    }
}
