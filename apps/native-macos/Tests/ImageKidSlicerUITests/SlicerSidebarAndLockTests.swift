import XCTest

/// The slices list: renaming a slice, locking it, and proving a locked slice
/// really is inert to the pointer.
final class SlicerSidebarAndLockTests: SlicerUITestCase {

    func testRenameLockAndDragThroughALockedSlice() throws {
        let scratch = try appScratchDirectory()
        let sheet = scratch.appendingPathComponent("sheet.png")
        try writeSheet(to: sheet)

        let saveFolder = uniqueSaveFolderName("slices")
        let app = launchApp(openImage: sheet, saveFolderName: saveFolder)
        let window = app.windows.firstMatch
        assertAppears(window, timeout: 20)

        drag(window, from: CGVector(dx: 0.22, dy: 0.32), to: CGVector(dx: 0.45, dy: 0.62))
        waitForLabel(sliceCount(app), "1 slice")

        // The list is off until asked for.
        XCTAssertFalse(toolbarButton(app, "slicer.sidebar").exists)
        toolbarButton(app, "slicer.sidebarToggle").click()
        assertAppears(toolbarButton(app, "slicer.sidebar"))

        // Rename it, and the canvas label follows.
        let field = app.textFields["slicer.row.name.0"].firstMatch
        assertAppears(field)
        field.click()
        field.typeText("hero\r")
        assertAppears(slice(app, named: "hero"))

        // Lock it.
        toolbarButton(app, "slicer.row.lock.0").click()
        let hero = slice(app, named: "hero")
        assertAppears(hero)
        let lockedGeometry = try XCTUnwrap(hero.value as? String)
        XCTAssertTrue(lockedGeometry.hasPrefix("Locked"), "got \(lockedGeometry)")

        // Dragging from inside a locked slice draws a new one instead of
        // picking the locked one up.
        hero.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
            .press(forDuration: 0.2, thenDragTo: hero.coordinate(withNormalizedOffset: CGVector(dx: 1.6, dy: 1.6)))

        waitForLabel(sliceCount(app), "2 slices")
        XCTAssertEqual(
            slice(app, named: "hero").value as? String,
            lockedGeometry,
            "the locked slice must not have moved")

        // Both export, and the rename drives the filename.
        let save = app.buttons["slicer.save"].firstMatch
        assertAppears(save)
        save.click()
        waitForLabel(exportSummary(app), "Saved 2 slices to \(saveFolder).")
    }
}
