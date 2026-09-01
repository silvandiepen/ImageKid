import XCTest

/// The slice inspector: double-click a slice, rename it, and type an exact
/// size that grows from a chosen anchor.
final class SlicerInspectorTests: SlicerUITestCase {

    func testDoubleClickRenamesAndResizesFromAnAnchor() throws {
        let scratch = try appScratchDirectory()
        let sheet = scratch.appendingPathComponent("sheet.png")
        try writeSheet(to: sheet, width: 800, height: 600)

        let saveFolder = uniqueSaveFolderName("slices")
        let app = launchApp(openImage: sheet, saveFolderName: saveFolder)
        let window = app.windows.firstMatch
        assertAppears(window, timeout: 20)

        drag(window, from: CGVector(dx: 0.30, dy: 0.35), to: CGVector(dx: 0.55, dy: 0.60))
        waitForLabel(sliceCount(app), "1 slice")

        slice(app, named: "Slice 1").doubleClick()

        let nameField = app.textFields["slicer.inspector.name"].firstMatch
        assertAppears(nameField, "double-clicking a slice should open its inspector")

        // Rename, and the canvas label follows.
        nameField.click()
        nameField.typeText("hero\r")
        assertAppears(slice(app, named: "hero"))

        // Hold the top-left corner, then type an exact size.
        toolbarButton(app, "slicer.inspector.anchor.topLeft").click()
        let before = try XCTUnwrap(slice(app, named: "hero").value as? String)
        let origin = try XCTUnwrap(before.components(separatedBy: " at ").last)

        let widthField = app.textFields["slicer.inspector.width"].firstMatch
        assertAppears(widthField)
        // Double-click selects the existing number so the new one replaces it.
        widthField.doubleClick()
        widthField.typeText("240\r")

        let heightField = app.textFields["slicer.inspector.height"].firstMatch
        heightField.doubleClick()
        heightField.typeText("120\r")

        let after = try XCTUnwrap(slice(app, named: "hero").value as? String)
        XCTAssertTrue(after.hasPrefix("240 by 120 pixels"), "got \(after)")
        XCTAssertEqual(
            after.components(separatedBy: " at ").last,
            origin,
            "the top-left anchor must hold the corner still")

        // The rename drives the exported filename.
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        let save = app.buttons["slicer.save"].firstMatch
        assertAppears(save)
        save.click()
        waitForLabel(exportSummary(app), "Saved 1 slice to \(saveFolder).")
    }
}
