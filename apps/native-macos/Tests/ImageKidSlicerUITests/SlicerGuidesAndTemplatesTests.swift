import XCTest

/// The toolbar half of the app: cutting guides feeding Auto Slice, and
/// templates laying a whole grid of slices down in one click.
final class SlicerGuidesAndTemplatesTests: SlicerUITestCase {

    func testGuidesFeedAutoSlice() throws {
        let scratch = try appScratchDirectory()
        let sheet = scratch.appendingPathComponent("sheet.png")
        try writeSheet(to: sheet)

        let app = launchApp(openImage: sheet, saveFolderName: uniqueSaveFolderName("slices"))
        let window = app.windows.firstMatch
        assertAppears(window, timeout: 20)
        waitForLabel(sliceCount(app), "No slices yet")

        let autoSlice = toolbarButton(app, "slicer.autoSlice")
        assertAppears(autoSlice)
        XCTAssertFalse(autoSlice.isEnabled, "Auto Slice needs a cutting line first")

        toolbarButton(app, "slicer.tool.guides").click()

        // A sideways sweep lays down a horizontal cut; an upright one a
        // vertical cut. Together they quarter the sheet.
        drag(window, from: CGVector(dx: 0.25, dy: 0.45), to: CGVector(dx: 0.75, dy: 0.45))
        assertAppears(slice(app, named: "Horizontal guide"))

        drag(window, from: CGVector(dx: 0.50, dy: 0.30), to: CGVector(dx: 0.50, dy: 0.65))
        assertAppears(slice(app, named: "Vertical guide"))

        // A selected guide is deleted by Backspace, exactly like a slice.
        drag(window, from: CGVector(dx: 0.35, dy: 0.60), to: CGVector(dx: 0.65, dy: 0.60))
        app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])

        XCTAssertTrue(autoSlice.isEnabled, "two guides should enable Auto Slice")
        autoSlice.click()
        waitForLabel(sliceCount(app), "4 slices")

        // Clearing the guides leaves the slices they produced alone.
        toolbarButton(app, "slicer.clearGuides").click()
        waitForDisappearance(slice(app, named: "Vertical guide"))
        waitForLabel(sliceCount(app), "4 slices")
    }

    func testTemplateLaysOutTheWholeImage() throws {
        let scratch = try appScratchDirectory()
        let sheet = scratch.appendingPathComponent("sheet.png")
        try writeSheet(to: sheet)

        let saveFolder = uniqueSaveFolderName("slices")
        let app = launchApp(openImage: sheet, saveFolderName: saveFolder)
        assertAppears(app.windows.firstMatch, timeout: 20)
        waitForLabel(sliceCount(app), "No slices yet")

        toolbarButton(app, "slicer.templates").click()
        let quarters = toolbarButton(app, "slicer.template.2x2")
        assertAppears(quarters, "the Templates popover should list the built-ins")
        quarters.click()

        waitForLabel(sliceCount(app), "4 slices")
        assertAppears(slice(app, named: "Slice 4"))

        // And the whole set exports.
        let save = app.buttons["slicer.save"].firstMatch
        assertAppears(save)
        save.click()
        waitForLabel(exportSummary(app), "Saved 4 slices to \(saveFolder).")
    }
}
