import XCTest

/// The export settings sheet: tabs, and settings that survive closing it.
final class SlicerExportSheetTests: SlicerUITestCase {

    func testSettingAFixedSizeThroughTheSheetChangesWhatIsWritten() throws {
        let scratch = try appScratchDirectory()
        let collage = scratch.appendingPathComponent("collage.png")
        try writeCollage(to: collage)

        let saveFolder = uniqueSaveFolderName("sheet")
        let app = launchApp(openImage: collage, saveFolderName: saveFolder)
        assertAppears(app.windows.firstMatch, timeout: 20)

        toolbarButton(app, "slicer.detectElements").click()
        waitForLabel(sliceCount(app), "3 slices")

        toolbarButton(app, "slicer.exportOptions").click()
        assertAppears(toolbarButton(app, "slicer.export.sheet"), "the export sheet should open")

        // Format lives on the first tab.
        assertAppears(toolbarButton(app, "slicer.export.format"))

        // Size lives on the second.
        tab(app, "Size").click()
        let sizing = toolbarButton(app, "slicer.export.sizing")
        assertAppears(sizing, "the Size tab should show the sizing control")
        control(app, labelled: "Fixed size").click()

        let width = app.textFields["slicer.export.width"].firstMatch
        assertAppears(width)
        width.doubleClick()
        width.typeText("128")
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])

        let height = app.textFields["slicer.export.height"].firstMatch
        assertAppears(height)
        height.doubleClick()
        height.typeText("128")
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])

        // The summary reflects it without leaving the sheet.
        waitForLabel(toolbarButton(app, "slicer.export.summary"), "PNG · 128×128 contain")

        toolbarButton(app, "slicer.export.done").click()
        waitForDisappearance(toolbarButton(app, "slicer.export.sheet"))

        let save = app.buttons["slicer.save"].firstMatch
        assertAppears(save)
        save.click()
        waitForLabel(exportSummary(app), "Saved 3 slices to \(saveFolder).")
    }

    func testResetPutsTheSettingsBack() throws {
        let scratch = try appScratchDirectory()
        let sheet = scratch.appendingPathComponent("sheet.png")
        try writeSheet(to: sheet)

        let app = launchApp(openImage: sheet, saveFolderName: uniqueSaveFolderName("reset"))
        assertAppears(app.windows.firstMatch, timeout: 20)

        toolbarButton(app, "slicer.exportOptions").click()
        assertAppears(toolbarButton(app, "slicer.export.sheet"))

        tab(app, "Naming").click()
        let example = toolbarButton(app, "slicer.export.example.0")
        assertAppears(example)
        let original = try XCTUnwrap(example.value as? String ?? example.label as String?)

        let prefix = app.textFields["slicer.export.prefix"].firstMatch
        assertAppears(prefix)
        prefix.click()
        prefix.typeText("web")
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])

        // The example filename picks the prefix up straight away.
        waitForLabel(toolbarButton(app, "slicer.export.example.0"), "web-" + original)

        toolbarButton(app, "slicer.export.reset").click()
        waitForLabel(toolbarButton(app, "slicer.export.example.0"), original)

        toolbarButton(app, "slicer.export.done").click()
        waitForDisappearance(toolbarButton(app, "slicer.export.sheet"))
    }
}
