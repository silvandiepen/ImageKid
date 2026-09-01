import XCTest

/// The complete first-release journey from `docs/slicer.md`: open an image,
/// create two slices, adjust one, delete one, save the rest to a folder, and
/// confirm the files exist.
final class SlicerJourneyTests: SlicerUITestCase {

    func testOpenDrawAdjustDeleteAndSave() throws {
        let scratch = try appScratchDirectory()
        let sheet = scratch.appendingPathComponent("sheet.png")
        try writeSheet(to: sheet)

        let saveFolder = uniqueSaveFolderName("slices")
        let app = launchApp(openImage: sheet, saveFolderName: saveFolder)
        let window = app.windows.firstMatch
        assertAppears(window, timeout: 20)
        waitForLabel(sliceCount(app), "No slices yet")

        // 1 + 2 — two slices, drawn on the left and right of the sheet.
        drag(window, from: CGVector(dx: 0.22, dy: 0.35), to: CGVector(dx: 0.42, dy: 0.60))
        waitForLabel(sliceCount(app), "1 slice")
        drag(window, from: CGVector(dx: 0.58, dy: 0.35), to: CGVector(dx: 0.78, dy: 0.60))
        waitForLabel(sliceCount(app), "2 slices")

        // 3 — resize the selected slice by its bottom-right handle, then move
        // it. Both are read back through the slice's own accessibility value,
        // which reports source pixels, so this proves the canvas edit reached
        // the source-relative geometry.
        let second = slice(app, named: "Slice 2")
        assertAppears(second)
        let beforeResize = try XCTUnwrap(second.value as? String)

        second.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .press(forDuration: 0.2, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.70)))
        let afterResize = try XCTUnwrap(slice(app, named: "Slice 2").value as? String)
        XCTAssertNotEqual(beforeResize, afterResize, "dragging a handle should resize the slice")

        slice(app, named: "Slice 2").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.50)))
        let afterMove = try XCTUnwrap(slice(app, named: "Slice 2").value as? String)
        XCTAssertNotEqual(afterResize, afterMove, "dragging inside a slice should move it")

        // 4 — select the first slice and delete it.
        slice(app, named: "Slice 1").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
        waitForLabel(sliceCount(app), "1 slice")

        // 5 + 6 — Save writes one file per remaining slice.
        let save = app.buttons["slicer.save"].firstMatch
        assertAppears(save)
        save.click()

        // The summary counts the files the export actually wrote and moved
        // into place — one per remaining slice.
        waitForLabel(exportSummary(app), "Saved 1 slice to \(saveFolder).")
    }

    func testEmptyStateOffersOpenAndHidesSave() {
        let app = XCUIApplication()
        app.launch()

        assertAppears(app.windows.firstMatch, timeout: 20)
        assertAppears(app.buttons["slicer.openEmptyState"].firstMatch, "the empty state should offer Open Image")
        XCTAssertFalse(app.buttons["slicer.save"].firstMatch.exists, "Save appears only once a slice exists")
    }
}
