import CoreGraphics
import XCTest

@testable import BrushKit

final class BrushEngineTests: XCTestCase {

    /// A straight horizontal stroke of known length and constant pressure.
    private func straightStroke(length: Double, pressure: Double = 1, samples n: Int = 32)
        -> StrokeInput
    {
        var s: [StrokeSample] = []
        for i in 0...n {
            let t = Double(i) / Double(n)
            s.append(
                StrokeSample(
                    position: CGPoint(x: t * length, y: 50), pressure: pressure,
                    timestamp: t))
        }
        return StrokeInput(samples: s)
    }

    // MARK: Spacing

    func testDabSpacingMatchesBrushSpacing() {
        // No smoothing/jitter so the geometry is exact; constant pressure so the
        // diameter (hence the spacing step) is constant.
        var brush = Brush(name: "Test", tip: Brush.Tip(spacing: 0.1), size: 20)
        brush.smoothing = 0
        brush.dynamics = Brush.Dynamics(pressureToSize: 0, pressureToOpacity: 0)
        let dabs = BrushEngine.dabs(for: straightStroke(length: 200), brush: brush, color: .black)
        // step = spacing(0.1) × diameter(20) = 2pt over 200pt ≈ 100 gaps → ~101 dabs.
        XCTAssertEqual(Double(dabs.count), 101, accuracy: 2)
        // Consecutive dabs sit ~2pt apart along x.
        let dx = dabs[1].position.x - dabs[0].position.x
        XCTAssertEqual(dx, 2, accuracy: 0.5)
    }

    func testDenserSpacingProducesMoreDabs() {
        var dense = Brush(name: "Dense", tip: Brush.Tip(spacing: 0.03), size: 20)
        var sparse = Brush(name: "Sparse", tip: Brush.Tip(spacing: 0.2), size: 20)
        dense.smoothing = 0
        sparse.smoothing = 0
        let stroke = straightStroke(length: 200)
        let a = BrushEngine.dabs(for: stroke, brush: dense, color: .black).count
        let b = BrushEngine.dabs(for: stroke, brush: sparse, color: .black).count
        XCTAssertGreaterThan(a, b)
    }

    // MARK: Pressure dynamics

    func testPressureDrivesDiameter() {
        var brush = Brush(name: "P", tip: Brush.Tip(spacing: 0.1), size: 40)
        brush.smoothing = 0
        brush.dynamics = Brush.Dynamics(pressureToSize: 1, pressureToOpacity: 0)
        let hard = BrushEngine.dabs(for: straightStroke(length: 100, pressure: 1), brush: brush, color: .black)
        let soft = BrushEngine.dabs(for: straightStroke(length: 100, pressure: 0.25), brush: brush, color: .black)
        XCTAssertEqual(hard.first?.diameter ?? 0, 40, accuracy: 0.5)
        // pressureToSize 1, pressure 0.25 → diameter ≈ 40 × 0.25 = 10.
        XCTAssertEqual(soft.first?.diameter ?? 0, 10, accuracy: 1)
    }

    func testPressureDrivesAlpha() {
        var brush = Brush(name: "A", tip: Brush.Tip(spacing: 0.1), size: 20, flow: 1, opacity: 1)
        brush.smoothing = 0
        brush.dynamics = Brush.Dynamics(pressureToSize: 0, pressureToOpacity: 1)
        let soft = BrushEngine.dabs(for: straightStroke(length: 100, pressure: 0.5), brush: brush, color: .black)
        XCTAssertEqual(soft.first?.alpha ?? 0, 0.5, accuracy: 0.02)
    }

    func testOpacityCapsAlpha() {
        var brush = Brush(name: "Cap", tip: Brush.Tip(spacing: 0.1), size: 20, flow: 1, opacity: 0.4)
        brush.smoothing = 0
        brush.dynamics = Brush.Dynamics(pressureToSize: 0, pressureToOpacity: 0)
        let dabs = BrushEngine.dabs(for: straightStroke(length: 50), brush: brush, color: .black)
        XCTAssertLessThanOrEqual(dabs.first?.alpha ?? 1, 0.4 + 1e-6)
    }

    // MARK: Determinism

    func testJitterIsDeterministicForASeed() {
        var brush = Brush(name: "J", tip: Brush.Tip(spacing: 0.1, scatter: 0.5), size: 20)
        brush.smoothing = 0
        brush.dynamics = Brush.Dynamics(sizeJitter: 0.5, angleJitter: 0.5)
        let stroke = straightStroke(length: 200)
        let a = BrushEngine.dabs(for: stroke, brush: brush, color: .black, seed: 7)
        let b = BrushEngine.dabs(for: stroke, brush: brush, color: .black, seed: 7)
        let c = BrushEngine.dabs(for: stroke, brush: brush, color: .black, seed: 8)
        XCTAssertEqual(a, b, "same seed ⇒ identical dabs")
        XCTAssertNotEqual(a, c, "a different seed ⇒ different jitter")
    }

    // MARK: Taper

    func testTaperThinsTheEnds() {
        var brush = Brush(name: "T", tip: Brush.Tip(spacing: 0.05), size: 30)
        brush.smoothing = 0
        brush.dynamics = Brush.Dynamics(pressureToSize: 0)
        brush.taper = Brush.Taper(startLength: 20, endLength: 20, startSize: 0, endSize: 0)
        let dabs = BrushEngine.dabs(for: straightStroke(length: 200), brush: brush, color: .black)
        let mid = dabs[dabs.count / 2].diameter
        XCTAssertLessThan(dabs.first!.diameter, mid, "start tapers thinner than the middle")
        XCTAssertLessThan(dabs.last!.diameter, mid, "end tapers thinner than the middle")
        XCTAssertEqual(mid, 30, accuracy: 1, "the middle keeps full width")
    }

    // MARK: Edge cases

    func testSingleTapLeavesOneDab() {
        let stroke = StrokeInput(samples: [StrokeSample(position: CGPoint(x: 10, y: 10))])
        let dabs = BrushEngine.dabs(for: stroke, brush: BrushLibrary.inkPen, color: .black)
        XCTAssertEqual(dabs.count, 1)
    }

    func testEmptyStrokeLeavesNoDabs() {
        XCTAssertTrue(BrushEngine.dabs(for: StrokeInput(), brush: BrushLibrary.inkPen, color: .black).isEmpty)
    }
}
