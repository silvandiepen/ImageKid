import XCTest

/// Editor-side smoke journeys: launch → draw → undo, select → style →
/// delete, and the floating-palette mechanics. Each test is its own fresh
/// app launch (deterministic `--uitest` environment) and asserts through
/// identifiers and the status-bar node count — no pixel reads.
final class EditorJourneyTests: FekthorUITestCase {

    /// Journey A: launch → home renders → ⌘N → editor appears → M → drag a
    /// rectangle out → the status bar counts one node → ⌘Z removes it.
    func testLaunchDrawUndo() {
        let app = launchApp()
        openBlankEditor(app)
        drawRect(app)
        // The edit marks the session dirty (the orange dot is on screen).
        XCTAssertTrue(element(app, "editor.dirtyDot").exists, "drawing should mark the file dirty")
        app.typeKey("z", modifierFlags: .command)
        waitForLabel(nodeCount(app), "0 nodes")
    }

    /// Journey B: draw a rect → V → click the shape's outline → the Fill
    /// palette's colour well is on screen → Backspace deletes the node.
    func testSelectFillWellAndDelete() {
        let app = launchApp()
        let window = app.windows.firstMatch
        openBlankEditor(app)
        drawRect(app)
        app.typeKey("v", modifierFlags: [])
        // New shapes are born fill-none, so hit the STROKE: the left edge
        // midpoint of the rect that was just dragged out.
        window.coordinate(
            withNormalizedOffset: CGVector(
                dx: Self.drawFrom.dx, dy: (Self.drawFrom.dy + Self.drawTo.dy) / 2)
        ).click()
        assertAppears(app.staticTexts["1 selected"], "clicking the outline should select the rect")
        assertAppears(element(app, "panel.fill.well"), "the Fill palette's colour well should exist")
        app.typeKey(.delete, modifierFlags: [])
        waitForLabel(nodeCount(app), "0 nodes")
    }

    /// Journey E: the rail chip toggles the History palette on and off, and
    /// a dragged palette header settles where it was dropped.
    func testPanelRailToggleAndHeaderDrag() {
        let app = launchApp()
        let window = app.windows.firstMatch
        openBlankEditor(app)

        // History is not in the first-run set: the chip opens it…
        let header = app.staticTexts["History"]
        XCTAssertFalse(header.exists, "History should start hidden in the default layout")
        element(app, "rail.history").click()
        assertAppears(header, "the rail chip should open the History palette")

        // …drag its header 100pt toward the window centre (grid-snapped on
        // release, so allow ±40pt) and it stays where it was dropped…
        let before = header.frame
        let dx: CGFloat = before.midX < window.frame.midX ? 100 : -100
        let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: dx, dy: 0)))
        assertAppears(header, "the palette should survive the drag")
        let moved = header.frame.midX - before.midX
        XCTAssertEqual(moved, dx, accuracy: 40, "the palette should settle ~100pt from its start")

        // …and the chip closes it again.
        element(app, "rail.history").click()
        waitForDisappearance(header)
    }
}
