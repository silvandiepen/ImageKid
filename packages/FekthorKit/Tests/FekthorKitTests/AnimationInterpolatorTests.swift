import XCTest

@testable import FekthorKit

final class AnimationInterpolatorTests: XCTestCase {

    // MARK: - Timing functions

    /// Independent reference: pure bisection on the bezier's x(t), no
    /// Newton — validates the production solver against straight math.
    private func referenceBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                                 at x: Double) -> Double {
        func sample(_ p1: Double, _ p2: Double, _ t: Double) -> Double {
            // Cubic bezier with endpoints 0 and 1.
            let u = 1 - t
            return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
        }
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if sample(x1, x2, mid) < x { lo = mid } else { hi = mid }
        }
        return sample(y1, y2, (lo + hi) / 2)
    }

    func testCubicBezierMatchesReferenceSolver() {
        let presets: [(Double, Double, Double, Double)] = [
            (0.25, 0.1, 0.25, 1),  // ease
            (0.42, 0, 1, 1),  // ease-in
            (0, 0, 0.58, 1),  // ease-out
            (0.42, 0, 0.58, 1),  // ease-in-out
            (0.68, -0.55, 0.27, 1.55),  // overshooting back-ease
            (0.95, 0.05, 0.8, 0.04),  // steep
        ]
        for (x1, y1, x2, y2) in presets {
            let f = TimingFunction.cubicBezier(x1, y1, x2, y2)
            for i in 0...20 {
                let x = Double(i) / 20
                XCTAssertEqual(
                    f.evaluate(x), referenceBezier(x1, y1, x2, y2, at: x), accuracy: 1e-3,
                    "cubic-bezier(\(x1),\(y1),\(x2),\(y2)) at \(x)")
            }
        }
        XCTAssertEqual(TimingFunction.ease.evaluate(0), 0)
        XCTAssertEqual(TimingFunction.ease.evaluate(1), 1)
    }

    func testStepsAllJumpPositions() {
        let end = TimingFunction.steps(4, .end)
        XCTAssertEqual(end.evaluate(0), 0)
        XCTAssertEqual(end.evaluate(0.24), 0)
        XCTAssertEqual(end.evaluate(0.25), 0.25)
        XCTAssertEqual(end.evaluate(0.99), 0.75)
        XCTAssertEqual(end.evaluate(1), 1)

        let start = TimingFunction.steps(4, .start)
        XCTAssertEqual(start.evaluate(0), 0.25)
        XCTAssertEqual(start.evaluate(0.25), 0.5)
        XCTAssertEqual(start.evaluate(1), 1)

        let both = TimingFunction.steps(2, .jumpBoth)
        XCTAssertEqual(both.evaluate(0), 1.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(both.evaluate(0.5), 2.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(both.evaluate(0.99), 2.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(both.evaluate(1), 1)

        let none = TimingFunction.steps(3, .jumpNone)
        XCTAssertEqual(none.evaluate(0.2), 0)
        XCTAssertEqual(none.evaluate(0.4), 0.5)
        XCTAssertEqual(none.evaluate(0.9), 1)
    }

    func testTimingFunctionParsing() {
        XCTAssertEqual(TimingFunction.parse("linear"), .linear)
        XCTAssertEqual(TimingFunction.parse("ease"), .ease)
        XCTAssertEqual(TimingFunction.parse("ease-out"), .easeOut)
        XCTAssertEqual(
            TimingFunction.parse("cubic-bezier(0.4, 0, 0.2, 1)"), .cubicBezier(0.4, 0, 0.2, 1))
        XCTAssertEqual(TimingFunction.parse("steps(3)"), .steps(3, .end))
        XCTAssertEqual(TimingFunction.parse("steps(1, end)"), .steps(1, .end))
        XCTAssertEqual(TimingFunction.parse("steps(2, jump-both)"), .steps(2, .jumpBoth))
        XCTAssertEqual(TimingFunction.parse("step-start"), .steps(1, .start))
        XCTAssertNil(TimingFunction.parse("bounce"))
        XCTAssertNil(TimingFunction.parse("steps(1, jump-none)"))
    }

    // MARK: - Clock semantics

    private func fadeBinding(
        trigger: String = "continuous", delay: Double = 0, iterations: String = "1",
        direction: String = "normal", fill: String = "none"
    ) -> (defs: [AnimationDef], binding: AnimationBinding) {
        let def = AnimationDef(
            name: "fade",
            keyframes: [
                AnimationKeyframe(offset: 0, declarations: ["opacity": "0"]),
                AnimationKeyframe(offset: 100, declarations: ["opacity": "1"]),
            ],
            timing: AnimationTiming(duration: 1, timingFunction: "linear"))
        let binding = AnimationBinding(
            animation: "fade", target: "fk-anim-fade", trigger: trigger,
            delay: delay, iterationCount: iterations, direction: direction, fillMode: fill)
        return ([def], binding)
    }

    private func opacity(
        _ fixture: (defs: [AnimationDef], binding: AnimationBinding), at time: Double,
        state: AnimationPreviewState = AnimationPreviewState()
    ) -> Double? {
        let overrides = AnimationInterpolator.resolve(
            defs: fixture.defs, bindings: [fixture.binding], settings: AnimationSettings(),
            time: time, state: state
        ) { _ in AnimationTargetContext(bounds: ViewBox(width: 24, height: 24)) }
        return overrides["fk-anim-fade"]?.opacity
    }

    func testDelayIterationDirectionFillMatrix() {
        // delay .5, duration 1, 2 iterations, alternate, no fill.
        var fx = fadeBinding(delay: 0.5, iterations: "2", direction: "alternate")
        XCTAssertNil(opacity(fx, at: 0), "before delay without backwards fill: no effect")
        XCTAssertEqual(opacity(fx, at: 1.0)!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(opacity(fx, at: 2.25)!, 0.25, accuracy: 1e-9, "second iteration reversed")
        XCTAssertNil(opacity(fx, at: 3.0), "past the end without forwards fill")

        fx = fadeBinding(delay: 0.5, iterations: "2", direction: "alternate", fill: "both")
        XCTAssertEqual(opacity(fx, at: 0)!, 0, accuracy: 1e-9, "backwards fill holds 0%")
        XCTAssertEqual(opacity(fx, at: 3.0)!, 0, accuracy: 1e-9,
                       "forwards fill holds the reversed end of iteration 2")

        fx = fadeBinding(iterations: "1", direction: "reverse", fill: "forwards")
        XCTAssertEqual(opacity(fx, at: 0.25)!, 0.75, accuracy: 1e-9)
        XCTAssertEqual(opacity(fx, at: 9)!, 0, accuracy: 1e-9, "reverse ends at 0%")
    }

    func testContinuousDefaultLoopsForever() {
        let fx = fadeBinding()  // iteration "1" explicit here
        XCTAssertEqual(opacity(fx, at: 0.5)!, 0.5, accuracy: 1e-9)
        // Default (unset) iteration on a continuous binding = infinite.
        let def = fx.defs[0]
        let binding = AnimationBinding(animation: "fade", target: "fk-anim-fade")
        let overrides = AnimationInterpolator.resolve(
            defs: [def], bindings: [binding], settings: AnimationSettings(),
            time: 100.25, state: AnimationPreviewState()
        ) { _ in AnimationTargetContext(bounds: ViewBox(width: 24, height: 24)) }
        XCTAssertEqual(overrides["fk-anim-fade"]?.opacity ?? -1, 0.25, accuracy: 1e-9)
    }

    func testTriggersGatePreview() {
        let fx = fadeBinding(trigger: "hover")
        XCTAssertNil(opacity(fx, at: 0.5))
        XCTAssertNotNil(opacity(fx, at: 0.5, state: AnimationPreviewState(hover: true)))
        XCTAssertNotNil(opacity(fx, at: 0.5, state: AnimationPreviewState(forcePlay: true)))

        let gated = fadeBinding(trigger: "parent-class:live")
        XCTAssertNil(opacity(gated, at: 0.5))
        XCTAssertNotNil(
            opacity(gated, at: 0.5, state: AnimationPreviewState(gateClasses: ["live"])))

        let manual = fadeBinding(trigger: "manual")
        XCTAssertNil(opacity(manual, at: 0.5))
        XCTAssertNotNil(opacity(manual, at: 0.5, state: AnimationPreviewState(forcePlay: true)))
    }

    func testImplicitFramesHoldBaseValue() {
        // Only a 50% frame: implicit 0%/100% take the element's base (0.8).
        let def = AnimationDef(
            name: "dip",
            keyframes: [AnimationKeyframe(offset: 50, declarations: ["opacity": "0"])],
            timing: AnimationTiming(duration: 1, timingFunction: "linear"))
        let binding = AnimationBinding(animation: "dip", target: "t", iterationCount: "1")
        func opacityAt(_ t: Double) -> Double? {
            AnimationInterpolator.resolve(
                defs: [def], bindings: [binding], settings: AnimationSettings(),
                time: t, state: AnimationPreviewState()
            ) { _ in
                AnimationTargetContext(bounds: ViewBox(width: 24, height: 24), baseOpacity: 0.8)
            }["t"]?.opacity
        }
        XCTAssertEqual(opacityAt(0.25)!, 0.4, accuracy: 1e-9)
        XCTAssertEqual(opacityAt(0.5)!, 0, accuracy: 1e-9)
        XCTAssertEqual(opacityAt(0.75)!, 0.4, accuracy: 1e-9)
    }

    func testDrawNormalizesAgainstRealPathLength() {
        let binding = AnimationBinding(
            animation: "draw", target: "fk-anim-draw", trigger: "continuous",
            iterationCount: "1", timingFunction: "linear")
        let overrides = AnimationInterpolator.resolve(
            defs: [AnimationPresets.draw], bindings: [binding], settings: AnimationSettings(),
            time: 0.3, state: AnimationPreviewState()  // duration .6 → halfway
        ) { _ in
            AnimationTargetContext(bounds: ViewBox(width: 24, height: 24), pathLength: 50)
        }
        let o = overrides["fk-anim-draw"]
        XCTAssertEqual(o?.strokeDashoffset ?? -1, 25, accuracy: 1e-9)
        XCTAssertEqual(o?.strokeDasharray ?? -1, 50, accuracy: 1e-9)
    }

    func testSRGBColorLerp() {
        let def = AnimationDef(
            name: "tint",
            keyframes: [
                AnimationKeyframe(offset: 0, declarations: ["fill": "#000000"]),
                AnimationKeyframe(offset: 100, declarations: ["fill": "#ff0000"]),
            ],
            timing: AnimationTiming(duration: 1, timingFunction: "linear"))
        let binding = AnimationBinding(animation: "tint", target: "t", iterationCount: "1")
        let overrides = AnimationInterpolator.resolve(
            defs: [def], bindings: [binding], settings: AnimationSettings(),
            time: 0.5, state: AnimationPreviewState()
        ) { _ in AnimationTargetContext(bounds: ViewBox(width: 24, height: 24)) }
        guard case .color(let r, let g, let b) = overrides["t"]?.fill else {
            return XCTFail("expected a color")
        }
        XCTAssertEqual(r, 128)
        XCTAssertEqual(g, 0)
        XCTAssertEqual(b, 0)
    }

    func testRotationMatrixAboutCenter() {
        let binding = AnimationBinding(
            animation: "spin", target: "fk-anim-spin", timingFunction: "linear")
        // spin duration .8 → t = .2 is 25% → 90°.
        let overrides = AnimationInterpolator.resolve(
            defs: [AnimationPresets.spin], bindings: [binding], settings: AnimationSettings(),
            time: 0.2, state: AnimationPreviewState()
        ) { _ in
            AnimationTargetContext(bounds: ViewBox(minX: 0, minY: 0, width: 24, height: 24))
        }
        guard let m = overrides["fk-anim-spin"]?.transform else {
            return XCTFail("expected a transform")
        }
        // 90° about (12,12) maps (12,4) → (20,12).
        let x = m[0] * 12 + m[2] * 4 + m[4]
        let y = m[1] * 12 + m[3] * 4 + m[5]
        XCTAssertEqual(x, 20, accuracy: 1e-9)
        XCTAssertEqual(y, 12, accuracy: 1e-9)
    }

    func testPercentTranslateUsesBounds() {
        let def = AnimationDef(
            name: "hop",
            keyframes: [
                AnimationKeyframe(offset: 0, declarations: ["transform": "translateY(0)"]),
                AnimationKeyframe(offset: 100, declarations: ["transform": "translateY(-50%)"]),
            ],
            timing: AnimationTiming(duration: 1, timingFunction: "linear"))
        let binding = AnimationBinding(
            animation: "hop", target: "t", iterationCount: "1", fillMode: "forwards")
        let overrides = AnimationInterpolator.resolve(
            defs: [def], bindings: [binding], settings: AnimationSettings(),
            time: 1, state: AnimationPreviewState()
        ) { _ in
            AnimationTargetContext(bounds: ViewBox(minX: 0, minY: 0, width: 24, height: 32))
        }
        guard let m = overrides["t"]?.transform else { return XCTFail("expected transform") }
        XCTAssertEqual(m[5], -16, accuracy: 1e-9, "translateY(-50%) of a 32-high box")
        XCTAssertEqual(m[4], 0, accuracy: 1e-9)
    }

    func testVisibilityInterpolatesLikeCSS() {
        let overrides = { (t: Double) -> Bool? in
            AnimationInterpolator.resolve(
                defs: [AnimationPresets.blink],
                bindings: [
                    AnimationBinding(
                        animation: "blink", target: "t", iterationCount: "1",
                        timingFunction: "steps(1, end)")
                ],
                settings: AnimationSettings(), time: t, state: AnimationPreviewState()
            ) { _ in AnimationTargetContext(bounds: ViewBox(width: 24, height: 24)) }["t"]?
                .hidden
        }
        // blink: visible → hidden at 50% → visible, steps(1,end) easing.
        XCTAssertEqual(overrides(0.1), false)
        XCTAssertEqual(overrides(0.6), true)
        XCTAssertEqual(overrides(0.99), true)
    }
}
