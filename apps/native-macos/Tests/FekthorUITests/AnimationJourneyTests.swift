import XCTest

/// The animation authoring journey: apply a preset from the Animation
/// palette, see its track + keyframes in the timeline drawer, run the
/// transport, and undo the binding away.
final class AnimationJourneyTests: FekthorUITestCase {

    func testApplyPresetTimelineAndUndo() {
        let app = launchApp()
        openBlankEditor(app)
        drawRect(app)

        // Open the Animation palette from the rail and apply "spin".
        element(app, "rail.animation").click()
        assertAppears(element(app, "animation.apply"), "the Animation palette should open")
        element(app, "animation.apply").click()
        let spin = app.menuItems["spin"]
        assertAppears(spin, "the apply menu should list the built-in presets")
        spin.click()

        // The timeline drawer shows the new track with its keyframes.
        element(app, "animation.timeline").click()
        assertAppears(element(app, "timeline.drawer"))
        assertAppears(
            element(app, "timeline.keyframe"),
            "the spin track should show keyframe diamonds")

        // Transport runs (and pauses) without touching the document.
        let play = element(app, "timeline.play")
        play.click()
        play.click()

        // Undo removes the binding — the timeline empties again.
        app.typeKey("z", modifierFlags: .command)
        waitForDisappearance(element(app, "timeline.keyframe"))
    }
}
