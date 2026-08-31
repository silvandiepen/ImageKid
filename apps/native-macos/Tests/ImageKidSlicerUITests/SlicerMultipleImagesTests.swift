import XCTest

/// The filmstrip: several images open at once, one layout applied across them,
/// and a single Export All run.
final class SlicerMultipleImagesTests: SlicerUITestCase {

    func testApplyOneLayoutAcrossImagesAndExportThemAll() throws {
        let scratch = try appScratchDirectory()
        let first = scratch.appendingPathComponent("alpha.png")
        let second = scratch.appendingPathComponent("beta.png")
        try writeSheet(to: first, width: 800, height: 600)
        try writeSheet(to: second, width: 600, height: 900)

        let saveFolder = uniqueSaveFolderName("all")
        let app = launchApp(openImages: [first, second], saveFolderName: saveFolder)
        assertAppears(app.windows.firstMatch, timeout: 20)

        // Both images are in the strip, in the order they were given, and
        // opening several selects the first of them.
        assertAppears(toolbarButton(app, "slicer.filmstrip"), "a second image should reveal the filmstrip")
        assertAppears(toolbarButton(app, "slicer.film.alpha"))
        assertAppears(toolbarButton(app, "slicer.film.beta"))
        waitForLabel(sliceCount(app), "No slices yet")

        // Lay a template over the current image only.
        toolbarButton(app, "slicer.templates").click()
        toolbarButton(app, "slicer.template.2x2").click()
        waitForLabel(sliceCount(app), "4 slices")

        // The other image is still untouched.
        toolbarButton(app, "slicer.film.beta").click()
        waitForLabel(sliceCount(app), "No slices yet")

        // Apply the layout from the image that has one, to all.
        toolbarButton(app, "slicer.film.alpha").click()
        waitForLabel(sliceCount(app), "4 slices")
        app.menuBars.menuBarItems["Slice"].click()
        app.menuItems["Apply Layout to All Images"].click()

        toolbarButton(app, "slicer.film.beta").click()
        waitForLabel(sliceCount(app), "4 slices")

        // One run writes both images, each into its own folder.
        let exportAll = app.buttons["slicer.exportAll"].firstMatch
        assertAppears(exportAll)
        exportAll.click()
        waitForLabel(exportSummary(app), "Saved 8 files from 2 images to \(saveFolder).")
    }
}
