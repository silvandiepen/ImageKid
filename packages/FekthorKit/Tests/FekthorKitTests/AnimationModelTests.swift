import XCTest

@testable import FekthorKit

final class AnimationModelTests: XCTestCase {

    private var spinBinding: AnimationBinding {
        AnimationBinding(animation: "spin", target: "fk-anim-spin", trigger: "continuous")
    }

    // MARK: - Codable

    func testDefRoundTripsThroughCodable() throws {
        let def = AnimationPresets.pulse
        let data = try JSONEncoder().encode(def)
        let back = try JSONDecoder().decode(AnimationDef.self, from: data)
        XCTAssertEqual(back, def)
    }

    func testBindingAndSettingsRoundTrip() throws {
        let binding = AnimationBinding(
            animation: "draw", target: "fk-anim-draw", trigger: "hover",
            duration: 1.5, delay: 0.2, iterationCount: "2", fillMode: "forwards")
        let settings = AnimationSettings(
            enabled: false, defaultTrigger: "hover", classPrefix: "ik-")
        let bindingBack = try JSONDecoder().decode(
            AnimationBinding.self, from: JSONEncoder().encode(binding))
        let settingsBack = try JSONDecoder().decode(
            AnimationSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(bindingBack, binding)
        XCTAssertEqual(settingsBack, settings)
    }

    func testWorkfileWithAnimationsEncodesDeterministically() throws {
        let workfile = Workfile(
            settings: Workfile.WorkspaceSettings(
                animations: AnimationSettings(defaultDuration: 1.0)),
            animations: [AnimationPresets.spin, AnimationPresets.draw])
        let first = try workfile.encoded()
        let second = try workfile.encoded()
        XCTAssertEqual(first, second)
        let back = try Workfile.decode(first)
        XCTAssertEqual(back, workfile)
    }

    func testOldWorkfileJSONStillDecodes() throws {
        // A pre-animation workfile knows nothing of the new keys.
        let json = "{\"version\":1,\"swatches\":[\"#010101\"]}"
        let workfile = try Workfile.decode(Data(json.utf8))
        XCTAssertNil(workfile.animations)
        XCTAssertNil(workfile.settings?.animations)
        XCTAssertEqual(workfile.swatches, ["#010101"])
    }

    // MARK: - FileMeta carriage

    func testMetaWithAnimationsRoundTripsThroughWriterAndReader() throws {
        let meta = FileMeta.Meta(
            animations: [AnimationPresets.spin],
            animationBindings: [spinBinding])
        var doc = GraphicDocument.blank(width: 24, height: 24)
        doc = FileMeta.writing(meta, to: doc)
        let svg = SVGWriter.write(doc)
        let reread = try SVGReader.read(svg)
        XCTAssertEqual(FileMeta.read(from: reread), meta)
        XCTAssertEqual(SVGWriter.write(FileMeta.writing(meta, to: reread)), svg)
    }

    func testMetaIsEmptyCoversAnimationFields() {
        XCTAssertTrue(FileMeta.Meta().isEmpty)
        XCTAssertFalse(FileMeta.Meta(animationBindings: [spinBinding]).isEmpty)
        XCTAssertFalse(FileMeta.Meta(animationsEnabled: false).isEmpty)
        XCTAssertFalse(
            FileMeta.Meta(animationSettings: AnimationSettings(defaultDuration: 2)).isEmpty)
        // Empty arrays normalize away entirely.
        let doc = FileMeta.writing(
            FileMeta.Meta(animations: [], animationBindings: []),
            to: GraphicDocument.blank(width: 24, height: 24))
        XCTAssertNil(FileMeta.read(from: doc))
    }

    // MARK: - Triggers

    func testTriggerParsing() {
        XCTAssertEqual(AnimationTrigger.parse("continuous"), .continuous)
        XCTAssertEqual(AnimationTrigger.parse("hover"), .hover)
        XCTAssertEqual(AnimationTrigger.parse("parent-class:live"), .parentClass("live"))
        XCTAssertNil(AnimationTrigger.parse("parent-class:"))
        XCTAssertNil(AnimationTrigger.parse("sparkle"))
        XCTAssertNil(AnimationTrigger.parse(nil))
        for trigger in [AnimationTrigger.continuous, .hover, .focus, .active,
                        .parentClass("x"), .manual] {
            XCTAssertEqual(AnimationTrigger.parse(trigger.rawValue), trigger)
        }
    }

    // MARK: - Settings cascade

    func testSettingsResolutionIconOverridesWorkspace() {
        let workspace = AnimationSettings(
            defaultTrigger: "continuous", defaultDuration: 1.0, classPrefix: "fk-")
        let icon = AnimationSettings(defaultDuration: 0.25, reducedMotion: "ignore")
        let resolved = AnimationSettings.resolved(workspace: workspace, icon: icon)
        XCTAssertEqual(resolved.defaultDuration, 0.25)
        XCTAssertEqual(resolved.defaultTrigger, "continuous")
        XCTAssertEqual(resolved.classPrefix, "fk-")
        XCTAssertEqual(resolved.reducedMotion, "ignore")
        XCTAssertEqual(
            AnimationSettings.resolved(workspace: nil, icon: nil), AnimationSettings())
    }

    // MARK: - Normalization

    func testNormalizedSortsKeyframesStably() {
        var def = AnimationPresets.pulse
        def.keyframes = [def.keyframes[2], def.keyframes[0], def.keyframes[1]]
        XCTAssertEqual(def.normalized().keyframes.map(\.offset), [0, 50, 100])
    }

    // MARK: - Lint

    func testAllPresetsPassLint() {
        for preset in AnimationPresets.all {
            XCTAssertEqual(
                AnimationLint.validate(preset).filter { $0.severity == .error }, [],
                "preset \(preset.name) should lint clean")
        }
    }

    func testLintRejectsUnknownAndUnsafeValues() {
        let bad = AnimationDef(
            name: "bad name!",
            keyframes: [
                AnimationKeyframe(offset: 120, declarations: ["display": "none"]),
                AnimationKeyframe(offset: 0, declarations: ["fill": "red;} svg{display:none"]),
            ])
        let messages = AnimationLint.validate(bad)
        XCTAssertTrue(messages.contains { $0.message.contains("not a valid identifier") })
        XCTAssertTrue(messages.contains { $0.message.contains("outside 0–100") })
        XCTAssertTrue(messages.contains { $0.message.contains("not animatable") })
        XCTAssertTrue(messages.contains { $0.message.contains("unsafe value") })
    }

    func testLintRejectsDuplicateTargetsAndUnknownRefs() {
        let defs = [AnimationPresets.spin]
        let sibling = spinBinding
        let duplicate = AnimationBinding(animation: "spin", target: "fk-anim-spin")
        let unknownRef = AnimationBinding(animation: "zoom", target: "fk-anim-zoom")
        XCTAssertTrue(
            AnimationLint.validate(duplicate, defs: defs, siblings: [sibling])
                .contains { $0.message.contains("duplicate target") })
        XCTAssertTrue(
            AnimationLint.validate(unknownRef, defs: defs, siblings: [])
                .contains { $0.message.contains("unknown animation") })
        XCTAssertEqual(
            AnimationLint.validate(spinBinding, defs: defs, siblings: []), [])
    }

    func testLintValidatesGateClass() {
        let gated = AnimationBinding(
            animation: "spin", target: "fk-anim-spin", trigger: "parent-class:my panel")
        XCTAssertTrue(
            AnimationLint.validate(gated, defs: [AnimationPresets.spin], siblings: [])
                .contains { $0.message.contains("not a valid class") })
    }
}
