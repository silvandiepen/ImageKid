import XCTest

/// Suggest Guides: find the gutters in a tiled sheet, then cut along them.
final class SlicerSuggestGuidesTests: SlicerUITestCase {

    func testSuggestedGuidesCutASheetIntoItsTiles() throws {
        let scratch = try appScratchDirectory()
        let sheet = scratch.appendingPathComponent("tiles.png")
        try writeTiledSheet(to: sheet, columns: 3, rows: 2)

        let saveFolder = uniqueSaveFolderName("tiles")
        let app = launchApp(openImage: sheet, saveFolderName: saveFolder)
        assertAppears(app.windows.firstMatch, timeout: 20)
        waitForLabel(sliceCount(app), "No slices yet")

        // Auto Slice has nothing to cut along yet.
        XCTAssertFalse(toolbarButton(app, "slicer.autoSlice").isEnabled)

        toolbarButton(app, "slicer.suggestGuides").click()
        assertAppears(slice(app, named: "Vertical guide"), "a gutter should become a guide")
        assertAppears(slice(app, named: "Horizontal guide"))

        let autoSlice = toolbarButton(app, "slicer.autoSlice")
        XCTAssertTrue(autoSlice.isEnabled)
        autoSlice.click()

        // Three columns by two rows.
        waitForLabel(sliceCount(app), "6 slices")

        let save = app.buttons["slicer.save"].firstMatch
        assertAppears(save)
        save.click()
        waitForLabel(exportSummary(app), "Saved 6 slices to \(saveFolder).")
    }
}
