import XCTest

/// The Crop tool: pick one region and save it straight out as a file.
final class SlicerCropTests: SlicerUITestCase {

    func testCropOneRegionAndSaveItDirectly() throws {
        let scratch = try appScratchDirectory()
        let sheet = scratch.appendingPathComponent("sheet.png")
        try writeSheet(to: sheet, width: 800, height: 600)

        let saveFolder = uniqueSaveFolderName("crops")
        let app = launchApp(openImage: sheet, saveFolderName: saveFolder)
        let window = app.windows.firstMatch
        assertAppears(window, timeout: 20)
        waitForLabel(sliceCount(app), "No slices yet")

        // There is no Crop & Save until the Crop tool is chosen.
        XCTAssertFalse(app.buttons["slicer.cropSave"].firstMatch.exists)
        toolbarButton(app, "slicer.tool.crop").click()

        // Entering Crop starts from the whole image.
        waitForLabel(sliceCount(app), "Crop 800 × 600")

        // Drag a smaller region out.
        drag(window, from: CGVector(dx: 0.32, dy: 0.36), to: CGVector(dx: 0.62, dy: 0.64))
        let readout = try XCTUnwrap(sliceCount(app).label.isEmpty ? sliceCount(app).value as? String : sliceCount(app).label)
        XCTAssertTrue(readout.hasPrefix("Crop "), "got \(readout)")
        XCTAssertNotEqual(readout, "Crop 800 × 600", "the drag should have shrunk the region")

        let save = app.buttons["slicer.cropSave"].firstMatch
        assertAppears(save)
        save.click()
        waitForLabel(exportSummary(app), "Saved sheet-crop.png to \(saveFolder).")

        // Switching back to Slice leaves the crop behind and restores the
        // normal readout.
        toolbarButton(app, "slicer.tool.slice").click()
        waitForLabel(sliceCount(app), "No slices yet")
        XCTAssertFalse(app.buttons["slicer.cropSave"].firstMatch.exists)
    }
}
