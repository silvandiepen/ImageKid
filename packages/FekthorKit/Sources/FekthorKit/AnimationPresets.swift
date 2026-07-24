import Foundation

/// Built-in animation templates. These are NOT a hidden runtime library:
/// the compiler reads only workfile/FileMeta defs, so using a preset means
/// COPYING it into `Workfile.animations` (the UI's "Add preset"), where it
/// becomes an ordinary user-editable def — preset edits then propagate like
/// any other def edit.
public enum AnimationPresets {

    public static let all: [AnimationDef] = [
        spin, pulse, blink, draw, fadeIn, bounce, shake, wiggle,
    ]

    public static func named(_ name: String) -> AnimationDef? {
        all.first { $0.name == name }
    }

    public static let spin = AnimationDef(
        name: "spin",
        keyframes: [
            AnimationKeyframe(offset: 0, declarations: ["transform": "rotate(0deg)"]),
            AnimationKeyframe(offset: 100, declarations: ["transform": "rotate(360deg)"]),
        ],
        timing: AnimationTiming(duration: 0.8, timingFunction: "linear"))

    public static let pulse = AnimationDef(
        name: "pulse",
        keyframes: [
            AnimationKeyframe(offset: 0, declarations: ["transform": "scale(1)"]),
            AnimationKeyframe(
                offset: 50, declarations: ["transform": "scale(1.15)"], easing: "ease-out"),
            AnimationKeyframe(offset: 100, declarations: ["transform": "scale(1)"]),
        ],
        timing: AnimationTiming(duration: 1.2, timingFunction: "ease-in-out"))

    public static let blink = AnimationDef(
        name: "blink",
        keyframes: [
            AnimationKeyframe(offset: 0, declarations: ["visibility": "visible"]),
            AnimationKeyframe(offset: 50, declarations: ["visibility": "hidden"]),
            AnimationKeyframe(offset: 100, declarations: ["visibility": "visible"]),
        ],
        timing: AnimationTiming(duration: 1.0, timingFunction: "steps(1, end)"))

    /// Draw-on: dash keyframes on the normalized 0–100 `pathLength` ruler,
    /// so the same def draws any geometry.
    public static let draw = AnimationDef(
        name: "draw",
        keyframes: [
            AnimationKeyframe(offset: 0, declarations: ["stroke-dashoffset": "100"]),
            AnimationKeyframe(offset: 100, declarations: ["stroke-dashoffset": "0"]),
        ],
        timing: AnimationTiming(
            duration: 0.6, timingFunction: "ease", iterationCount: "1", fillMode: "forwards"),
        normalizesPathLength: true)

    public static let fadeIn = AnimationDef(
        name: "fade-in",
        keyframes: [
            AnimationKeyframe(offset: 0, declarations: ["opacity": "0"]),
            AnimationKeyframe(offset: 100, declarations: ["opacity": "1"]),
        ],
        timing: AnimationTiming(
            duration: 0.4, timingFunction: "ease-out", iterationCount: "1",
            fillMode: "forwards"))

    public static let bounce = AnimationDef(
        name: "bounce",
        keyframes: [
            AnimationKeyframe(
                offset: 0, declarations: ["transform": "translateY(0)"], easing: "ease-out"),
            AnimationKeyframe(
                offset: 40, declarations: ["transform": "translateY(-25%)"], easing: "ease-in"),
            AnimationKeyframe(
                offset: 70, declarations: ["transform": "translateY(0)"], easing: "ease-out"),
            AnimationKeyframe(
                offset: 85, declarations: ["transform": "translateY(-8%)"], easing: "ease-in"),
            AnimationKeyframe(offset: 100, declarations: ["transform": "translateY(0)"]),
        ],
        timing: AnimationTiming(duration: 0.9))

    public static let shake = AnimationDef(
        name: "shake",
        keyframes: [
            AnimationKeyframe(offset: 0, declarations: ["transform": "translateX(0)"]),
            AnimationKeyframe(offset: 20, declarations: ["transform": "translateX(-8%)"]),
            AnimationKeyframe(offset: 40, declarations: ["transform": "translateX(8%)"]),
            AnimationKeyframe(offset: 60, declarations: ["transform": "translateX(-6%)"]),
            AnimationKeyframe(offset: 80, declarations: ["transform": "translateX(6%)"]),
            AnimationKeyframe(offset: 100, declarations: ["transform": "translateX(0)"]),
        ],
        timing: AnimationTiming(duration: 0.5, timingFunction: "ease-in-out"))

    public static let wiggle = AnimationDef(
        name: "wiggle",
        keyframes: [
            AnimationKeyframe(offset: 0, declarations: ["transform": "rotate(0deg)"]),
            AnimationKeyframe(offset: 25, declarations: ["transform": "rotate(-6deg)"]),
            AnimationKeyframe(offset: 75, declarations: ["transform": "rotate(6deg)"]),
            AnimationKeyframe(offset: 100, declarations: ["transform": "rotate(0deg)"]),
        ],
        timing: AnimationTiming(duration: 0.6, timingFunction: "ease-in-out"))
}
