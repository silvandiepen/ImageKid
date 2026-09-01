import XCTest

/// Smoke tests for the core editor journeys on a regular-width iPad. Each test
/// launches a fresh app; `--uitest-image` loads a generated picture directly
/// so no test ever drives the photo picker.
final class ImageKidSmokeUITests: ImageKidUITestCase {

    // MARK: A — Launch

    func testLaunchEmptyStateOffersAddPhoto() {
        launch(withImage: false)
        waitFor("editor.emptyState")
        waitFor("empty.addButton")
        // No picture open → no editor toolbar.
        XCTAssertFalse(element("editor.toolbar").exists)
    }

    func testLaunchWithSampleImageShowsCanvasAndToolbar() {
        launch(withImage: true)
        waitFor("editor.viewCanvas")
        waitFor("editor.toolbar")
        waitFor("tool.draw")
        waitFor("tool.text")
        waitFor("tool.crop")
        waitFor("tool.mask")
        waitFor("topbar.layers")
        waitFor("topbar.history")
    }

    // MARK: B — Draw

    func testDrawStrokeThenToggleAndDeleteItsLayer() {
        launch(withImage: true)
        activateTool("tool.draw")
        waitFor("panel.annotate")
        waitFor("editor.canvas")

        // One freehand stroke across the middle of the picture.
        dragOnCanvas(from: (0.50, 0.50), to: (0.62, 0.60))

        waitFor("topbar.layers").tap()
        waitFor("panel.layers")
        XCTAssertTrue(poll { self.count("layers.row") == 1 }, "expected exactly one layer row")

        // Eye toggles visibility (label flips between Hide and Show).
        let eye = waitFor("layers.row.eye")
        XCTAssertEqual(eye.label, "Hide layer")
        eye.tap()
        XCTAssertTrue(poll { self.element("layers.row.eye").label == "Show layer" })
        element("layers.row.eye").tap()
        XCTAssertTrue(poll { self.element("layers.row.eye").label == "Hide layer" })

        // Select the row, delete it → the panel returns to its empty state.
        element("layers.row").tap()
        XCTAssertTrue(poll { (self.element("layers.row").value as? String) == "selected" })
        waitFor("layers.delete").tap()
        XCTAssertTrue(poll { self.count("layers.row") == 0 })
        waitFor("layers.empty")
    }

    // MARK: C — Text

    func testTextTypeCommitReeditAndClearDeletes() {
        launch(withImage: true)
        activateTool("tool.text")
        waitFor("panel.annotate")
        waitFor("editor.canvas")

        // Tap the canvas → inline editor appears; type.
        tapCanvas(0.50, 0.45)
        let editor = waitFor("canvas.text.editor")
        waitForKeyboardFocus(on: editor)
        app.typeText("Hello")

        // Tapping empty canvas commits; the text stays selected (border shows).
        tapCanvas(0.50, 0.15)
        waitGone("canvas.text.editor")
        waitFor("canvas.selectionBorder")

        // Double-tap the placed text → the inline editor reopens.
        canvasPoint(0.50, 0.45).withOffset(CGVector(dx: 24, dy: 16)).doubleTap()
        let reopened = waitFor("canvas.text.editor")
        waitForKeyboardFocus(on: reopened)

        // Clear the text (double-tap selects the word) and commit → the empty
        // text is discarded and nothing stays selected.
        reopened.doubleTap()
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        tapCanvas(0.50, 0.15)
        waitGone("canvas.text.editor")
        waitGone("canvas.selectionBorder")

        waitFor("topbar.layers").tap()
        waitFor("layers.empty")
        XCTAssertEqual(count("layers.row"), 0)
    }

    func testTextDeleteViaOptionsPanel() {
        launch(withImage: true)
        activateTool("tool.text")
        waitFor("editor.canvas")

        tapCanvas(0.45, 0.50)
        let editor = waitFor("canvas.text.editor")
        waitForKeyboardFocus(on: editor)
        app.typeText("Hi")
        tapCanvas(0.50, 0.15)
        waitGone("canvas.text.editor")
        waitFor("canvas.selectionBorder")

        // The committed text is still selected → the panel's delete is live.
        let delete = waitFor("annotate.deleteSelected")
        XCTAssertTrue(delete.isEnabled)
        delete.tap()
        waitGone("canvas.selectionBorder")

        waitFor("topbar.layers").tap()
        waitFor("layers.empty")
        XCTAssertEqual(count("layers.row"), 0)
    }

    // MARK: D — History

    func testCropCreatesHistoryStepAndOpenRowRestores() {
        launch(withImage: true)
        waitFor("topbar.undo")
        XCTAssertFalse(app.buttons["topbar.undo"].isEnabled)

        // Crop (full frame) is the scriptable one-tap history step.
        activateTool("tool.crop")
        waitFor("crop.apply").tap()
        XCTAssertTrue(poll { self.app.buttons["topbar.undo"].isEnabled }, "crop did not commit a history step")

        waitFor("topbar.history").tap()
        waitFor("panel.history")
        let openRow = waitFor("history.row.0")
        let cropRow = waitFor("history.row.1")
        XCTAssertTrue(openRow.label.contains("Open"))
        XCTAssertTrue(cropRow.label.contains("Cropped"))
        XCTAssertEqual(cropRow.value as? String, "current")
        XCTAssertEqual(openRow.value as? String, "past")

        // Jump back to "Open": the cursor moves, the crop step stays redoable.
        openRow.tap()
        XCTAssertTrue(poll { (self.element("history.row.0").value as? String) == "current" })
        XCTAssertEqual(element("history.row.1").value as? String, "future")
        waitFor("topbar.redo")
    }

    // MARK: E — Panels

    func testPanelHeaderDragMinimizeAndRestoreFromChip() {
        launch(withImage: true)
        activateTool("tool.draw")
        let panel = waitFor("panel.annotate")
        let before = panel.frame

        // Drag the panel by its header (top strip) 120pt right, 80pt down.
        // The dock grid-snaps to 20pt, hence the tolerance.
        let header = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.06))
        header.press(
            forDuration: 0.2,
            thenDragTo: header.withOffset(CGVector(dx: 120, dy: 80)),
            withVelocity: .slow,
            thenHoldForDuration: 0.2)
        XCTAssertTrue(poll {
            let frame = self.element("panel.annotate").frame
            return abs(frame.minX - before.minX - 120) <= 24
                && abs(frame.minY - before.minY - 80) <= 24
        }, "panel did not stay where the header drag left it")
        let moved = element("panel.annotate").frame

        // Minimize → the panel leaves the canvas; its rail chip restores it
        // in place. (The minimize control lives in the shared ImageKidKit
        // chrome, so it is addressed by its accessibility label.)
        app.buttons["Minimise Draw"].tap()
        waitGone("panel.annotate")
        waitFor("chip.annotate").tap()
        waitFor("panel.annotate")
        XCTAssertTrue(poll {
            let frame = self.element("panel.annotate").frame
            return abs(frame.minX - moved.minX) <= 24 && abs(frame.minY - moved.minY) <= 24
        }, "restored panel lost its dragged position")
    }
}
