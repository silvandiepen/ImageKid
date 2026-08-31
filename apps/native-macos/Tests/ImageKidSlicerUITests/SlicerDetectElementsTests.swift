import XCTest

/// Detect Elements: one slice around each separate thing, wherever it sits.
final class SlicerDetectElementsTests: SlicerUITestCase {

    func testDetectingElementsOnAScatteredLayout() throws {
        let scratch = try appScratchDirectory()
        let collage = scratch.appendingPathComponent("collage.png")
        try writeCollage(to: collage)

        let saveFolder = uniqueSaveFolderName("elements")
        let app = launchApp(openImage: collage, saveFolderName: saveFolder)
        assertAppears(app.windows.firstMatch, timeout: 20)
        waitForLabel(sliceCount(app), "No slices yet")

        toolbarButton(app, "slicer.detectElements").click()

        // Three boxes that share no full-width gutter: projection would give
        // four cells, element detection gives three slices.
        waitForLabel(sliceCount(app), "3 slices")

        let save = app.buttons["slicer.save"].firstMatch
        assertAppears(save)
        save.click()
        waitForLabel(exportSummary(app), "Saved 3 slices to \(saveFolder).")
    }
}
