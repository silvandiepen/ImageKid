import CoreGraphics
import XCTest

@testable import BrushKit

final class GrainTests: XCTestCase {

    func testNoiseIsInRangeAndDeterministic() {
        for _ in 0..<50 {
            let x = Double.random(in: 0...500)
            let y = Double.random(in: 0...500)
            let v = GrainNoise.value(x: x, y: y, cell: 6, seed: 12)
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
            // Same point → same value.
            XCTAssertEqual(v, GrainNoise.value(x: x, y: y, cell: 6, seed: 12), accuracy: 1e-12)
        }
    }

    func testNoiseVariesOverSpaceAndSeed() {
        let a = GrainNoise.value(x: 10, y: 10, cell: 6, seed: 1)
        let b = GrainNoise.value(x: 40, y: 90, cell: 6, seed: 1)
        let c = GrainNoise.value(x: 10, y: 10, cell: 6, seed: 2)
        XCTAssertNotEqual(a, b, accuracy: 0)  // different points differ
        XCTAssertNotEqual(a, c, accuracy: 0)  // different seeds differ
    }

    func testCoverageDepthZeroIsFull() {
        XCTAssertEqual(
            GrainNoise.coverage(x: 3, y: 7, cell: 6, depth: 0, seed: 1), 1, accuracy: 1e-12)
    }

    /// A single grained dab lays down LESS ink than the same dab without grain —
    /// the tooth leaves pits. (Isolated to one dab: with heavy opaque overlap a
    /// flow-1 brush legitimately fills the tooth in, so grain reads on low-flow
    /// media like the pencil/charcoal presets, not on a solid marker.)
    func testGrainReducesCoverageOnASingleDab() throws {
        let smooth = Dab(
            position: CGPoint(x: 50, y: 50), diameter: 60, angle: 0, roundness: 1,
            alpha: 1, hardness: 1, color: .black)
        let grained = Dab(
            position: CGPoint(x: 50, y: 50), diameter: 60, angle: 0, roundness: 1,
            alpha: 1, hardness: 1, color: .black, grainDepth: 0.8, grainCell: 6, grainSeed: 5)
        let size = CGSize(width: 100, height: 100)
        let smoothInk = totalAlpha(try XCTUnwrap(ReferenceRenderer.render(dabs: [smooth], size: size)))
        let grainedInk = totalAlpha(try XCTUnwrap(ReferenceRenderer.render(dabs: [grained], size: size)))
        XCTAssertLessThan(grainedInk, smoothInk * 0.9, "grain removes a visible fraction of the ink")
        XCTAssertGreaterThan(grainedInk, smoothInk * 0.2, "but paint still lands")
    }

    private func totalAlpha(_ image: CGImage) -> Double {
        guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
            return 0
        }
        var sum = 0.0
        let bpr = image.bytesPerRow
        for y in 0..<image.height {
            for x in 0..<image.width {
                sum += Double(ptr[y * bpr + x * 4 + 3])
            }
        }
        return sum
    }
}
