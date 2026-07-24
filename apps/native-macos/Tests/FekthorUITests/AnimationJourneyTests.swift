import XCTest

/// The animation authoring journey: apply a preset via Object ▸ Animate,
/// see its track + keyframes in the timeline drawer, run the transport,
/// and undo the binding away.
final class AnimationJourneyTests: FekthorUITestCase {

    func testApplyPresetTimelineAndUndo() {
        let app = launchApp()
        openBlankEditor(app)
        drawRect(app)

        // Apply "spin" from the menu bar (Object ▸ Animate ▸ spin) — the
        // path that works with any palette layout.
        let objectMenu = app.menuBars.menuBarItems["Object"]
        assertAppears(objectMenu, "the Object menu should exist")
        objectMenu.click()
        let animate = app.menuItems["Animate"]
        assertAppears(animate, "Object should offer the Animate submenu")
        animate.hover()
        let spin = app.menuItems["spin"]
        assertAppears(spin, "the Animate submenu should list the presets")
        spin.click()

        // The timeline drawer (⌥⌘T) shows the new track with keyframes.
        app.typeKey("t", modifierFlags: [.command, .option])
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
