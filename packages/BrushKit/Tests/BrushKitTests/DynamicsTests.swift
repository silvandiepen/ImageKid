import CoreGraphics
import XCTest

@testable import BrushKit

final class DynamicsTests: XCTestCase {

    private func stroke(pressure: Double = 1, altitude: Double = .pi / 2, azimuth: Double = 0)
        -> StrokeInput
    {
        StrokeInput(samples: (0...20).map {
            StrokeSample(
                position: CGPoint(x: Double($0) * 10, y: 50), pressure: pressure,
                altitude: altitude, azimuth: azimuth, timestamp: Double($0) * 0.01)
        })
    }

    // MARK: Response curves

    func testResponseCurveShapes() {
        XCTAssertEqual(ResponseCurve.linear.apply(0.5), 0.5, accuracy: 1e-9)
        XCTAssertLessThan(ResponseCurve.easeIn.apply(0.5), 0.5, "ease-in lags at the midpoint")
        XCTAssertGreaterThan(ResponseCurve.easeOut.apply(0.5), 0.5, "ease-out leads")
        XCTAssertEqual(ResponseCurve.easeInOut.apply(0), 0, accuracy: 1e-9)
        XCTAssertEqual(ResponseCurve.easeInOut.apply(1), 1, accuracy: 1e-9)
        // Clamped.
        XCTAssertEqual(ResponseCurve.linear.apply(2), 1)
        XCTAssertEqual(ResponseCurve.linear.apply(-1), 0)
    }

    func testPressureCurveChangesDiameterAtMidPressure() {
        var linear = Brush(name: "L", tip: Brush.Tip(spacing: 0.1), size: 40)
        linear.smoothing = 0
        linear.dynamics = Brush.Dynamics(pressureToSize: 1, pressureToOpacity: 0, pressureCurve: .linear)
        var eased = linear
        eased.dynamics.pressureCurve = .easeIn

        let s = stroke(pressure: 0.5)
        let dLinear = BrushEngine.dabs(for: s, brush: linear, color: .black).first!.diameter
        let dEased = BrushEngine.dabs(for: s, brush: eased, color: .black).first!.diameter
        // ease-in shrinks the effective pressure at 0.5, so a thinner dab.
        XCTAssertLessThan(dEased, dLinear)
    }

    // MARK: Tilt

    func testFlatTiltWidensWithTiltToSize() {
        var brush = Brush(name: "T", tip: Brush.Tip(spacing: 0.1), size: 20)
        brush.smoothing = 0
        brush.dynamics = Brush.Dynamics(pressureToSize: 0, pressureToOpacity: 0, tiltToSize: 1)
        let upright = BrushEngine.dabs(for: stroke(altitude: .pi / 2), brush: brush, color: .black).first!.diameter
        let flat = BrushEngine.dabs(for: stroke(altitude: 0), brush: brush, color: .black).first!.diameter
        XCTAssertEqual(upright, 20, accuracy: 0.5)
        XCTAssertEqual(flat, 40, accuracy: 1, "flat pen doubles the width at tiltToSize 1")
    }

    func testTiltToAngleFollowsAzimuth() {
        var brush = Brush(name: "A", tip: Brush.Tip(angle: 0, spacing: 0.1), size: 20)
        brush.smoothing = 0
        brush.dynamics = Brush.Dynamics(pressureToSize: 0, pressureToOpacity: 0, tiltToAngle: 1)
        let dab = BrushEngine.dabs(
            for: stroke(azimuth: .pi / 2), brush: brush, color: .black).first!
        XCTAssertEqual(dab.angle, .pi / 2, accuracy: 1e-6, "nib fully follows the azimuth")
    }

    // MARK: Hue jitter

    func testHueJitterVariesColourButKeepsItDeterministic() {
        var brush = Brush(name: "H", tip: Brush.Tip(spacing: 0.2), size: 20)
        brush.smoothing = 0
        brush.dynamics = Brush.Dynamics(pressureToSize: 0, pressureToOpacity: 0, hueJitter: 1)
        let red = RGBA(r: 1, g: 0, b: 0)
        let a = BrushEngine.dabs(for: stroke(), brush: brush, color: red, seed: 3)
        let b = BrushEngine.dabs(for: stroke(), brush: brush, color: red, seed: 3)
        XCTAssertEqual(a, b, "seeded hue jitter is reproducible")
        // At least one dab shifted off pure red.
        XCTAssertTrue(a.contains { $0.color != red }, "hue jitter changed some dabs' colour")
        // Hue rotation preserves the overall brightness ballpark (not black/white).
        for dab in a {
            let sum = dab.color.r + dab.color.g + dab.color.b
            XCTAssertGreaterThan(sum, 0.5)
        }
    }

    func testHueShiftRoundsThroughTheWheel() {
        let red = RGBA(r: 1, g: 0, b: 0)
        // A third of a turn from red ≈ green; two thirds ≈ blue.
        let green = red.hueShifted(by: 1.0 / 3)
        XCTAssertEqual(green.g, 1, accuracy: 1e-6)
        XCTAssertEqual(green.r, 0, accuracy: 1e-6)
        // A full turn is identity.
        let back = red.hueShifted(by: 1)
        XCTAssertEqual(back.r, 1, accuracy: 1e-6)
        XCTAssertEqual(back.g, 0, accuracy: 1e-6)
    }

    // MARK: Back-compat decode

    func testOldInkbrushWithoutCurvesStillDecodes() throws {
        // A brush JSON missing the new curve fields decodes with linear defaults.
        let json = """
            {"version":1,"brush":{"id":"x","name":"Old","size":20,"flow":1,"opacity":1,
            "smoothing":0,"blendMode":"normal",
            "tip":{"shape":"round","hardness":0.8,"roundness":1,"angle":0,"spacing":0.1,"scatter":0},
            "dynamics":{"pressureToSize":0.5,"pressureToOpacity":0.2,"pressureToFlow":0,
            "velocityToSize":0,"velocityToOpacity":0,"tiltToSize":0,"tiltToAngle":0,
            "sizeJitter":0,"angleJitter":0,"hueJitter":0},
            "grain":{"scale":1,"depth":0,"movingWithStroke":false},
            "taper":{"startLength":0,"endLength":0,"startSize":0,"endSize":0}}}
            """
        let brush = try InkBrushCoding.decode(Data(json.utf8))
        XCTAssertEqual(brush.dynamics.pressureCurve, .linear)
        XCTAssertEqual(brush.dynamics.velocityCurve, .linear)
        XCTAssertEqual(brush.dynamics.pressureToSize, 0.5)
    }
}
