import CoreGraphics
import XCTest

@testable import BrushKit

final class SmoothingAndTipTests: XCTestCase {

    // MARK: One-euro

    /// A jagged slow line gets pulled toward straight by the 1€ filter, while
    /// the endpoints stay pinned.
    func testOneEuroSmoothsTremorButKeepsEndpoints() {
        var samples: [StrokeSample] = []
        for i in 0...40 {
            // A straight rightward line with a small alternating y wobble.
            let wobble = (i % 2 == 0 ? 1.0 : -1.0) * 6
            samples.append(
                StrokeSample(
                    position: CGPoint(x: Double(i) * 5, y: 100 + wobble),
                    timestamp: Double(i) * 0.02))  // slow → strong smoothing
        }
        let raw = StrokeInput(samples: samples)
        let smooth = raw.oneEuroSmoothed(minCutoff: 0.6, beta: 0.02)

        func wobbleEnergy(_ input: StrokeInput) -> Double {
            input.samples.dropFirst().dropLast().reduce(0) {
                $0 + abs(Double($1.position.y) - 100)
            }
        }
        XCTAssertLessThan(
            wobbleEnergy(smooth), wobbleEnergy(raw) * 0.6, "the tremor is markedly reduced")
        XCTAssertEqual(smooth.samples.first!.position, raw.samples.first!.position)
        XCTAssertEqual(smooth.samples.last!.position, raw.samples.last!.position)
    }

    func testOneEuroPassesThroughWithoutTimestamps() {
        // No time deltas ⇒ nothing to filter; the spine is returned as-is.
        let input = StrokeInput(samples: [
            StrokeSample(position: CGPoint(x: 0, y: 0)),
            StrokeSample(position: CGPoint(x: 10, y: 30)),
            StrokeSample(position: CGPoint(x: 20, y: 0)),
        ])
        XCTAssertEqual(input.oneEuroSmoothed(minCutoff: 0.5, beta: 0.02), input)
    }

    /// Higher brush smoothing pulls a wobbly stroke closer to straight through
    /// the engine's live path.
    func testBrushSmoothingReducesDabDeviation() {
        var samples: [StrokeSample] = []
        for i in 0...40 {
            let wobble = (i % 2 == 0 ? 1.0 : -1.0) * 5
            samples.append(
                StrokeSample(
                    position: CGPoint(x: Double(i) * 5, y: 100 + wobble),
                    timestamp: Double(i) * 0.02))
        }
        let stroke = StrokeInput(samples: samples)
        func deviation(smoothing: Double) -> Double {
            var brush = Brush(name: "S", tip: Brush.Tip(spacing: 0.2), size: 6)
            brush.smoothing = smoothing
            brush.dynamics = Brush.Dynamics(pressureToSize: 0, pressureToOpacity: 0)
            let dabs = BrushEngine.dabs(for: stroke, brush: brush, color: .black)
            return dabs.reduce(0) { $0 + abs(Double($1.position.y) - 100) } / Double(dabs.count)
        }
        XCTAssertLessThan(deviation(smoothing: 0.9), deviation(smoothing: 0) * 0.8)
    }

    // MARK: Square tip

    func testSquareTipFillsTheCorners() throws {
        // A round dab leaves the tile corners clear; a square dab fills them.
        let size = CGSize(width: 60, height: 60)
        func corner(_ square: Bool) -> Double {
            let dab = Dab(
                position: CGPoint(x: 30, y: 30), diameter: 56, angle: 0, roundness: 1,
                alpha: 1, hardness: 1, color: .black, square: square)
            let image = ReferenceRenderer.render(dabs: [dab], size: size)!
            let data = image.dataProvider!.data!
            let ptr = CFDataGetBytePtr(data)!
            // Near a corner of the bounding square (x≈4,y≈4).
            return Double(ptr[4 * image.bytesPerRow + 4 * 4 + 3]) / 255
        }
        XCTAssertEqual(corner(false), 0, accuracy: 0.05, "round leaves the corner clear")
        XCTAssertGreaterThan(corner(true), 0.9, "square fills the corner")
    }

    func testEngineMarksSquareDabsFromTipShape() {
        var brush = Brush(name: "Sq", tip: Brush.Tip(shape: .square, spacing: 0.2), size: 20)
        brush.smoothing = 0
        let dabs = BrushEngine.dabs(
            for: StrokeInput(samples: [
                StrokeSample(position: CGPoint(x: 0, y: 0)),
                StrokeSample(position: CGPoint(x: 40, y: 0)),
            ]), brush: brush, color: .black)
        XCTAssertTrue(dabs.allSatisfy { $0.square })
    }
}
