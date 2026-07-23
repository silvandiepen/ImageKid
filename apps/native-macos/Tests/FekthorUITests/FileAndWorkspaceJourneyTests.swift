import XCTest

/// File and workspace smoke journeys: the ⌘S save flow through the real
/// NSSavePanel (steered into the app container with ⌘⇧G so the sandboxed
/// app keeps access across relaunches), and the `--uitest-workspace` gallery
/// flow over a fixture folder the test writes itself.
final class FileAndWorkspaceJourneyTests: FekthorUITestCase {

    // MARK: - Journey C: save, verify on disk, reopen

    func testSaveFlowAndReopen() throws {
        let dir = try appScratchDirectory()
        let name = "smoke-\(UUID().uuidString.prefix(8)).svg"
        let fileURL = dir.appendingPathComponent(name)

        let app = launchApp()
        openBlankEditor(app)
        drawRect(app)
        assertAppears(element(app, "editor.dirtyDot"), "drawing should mark the file dirty")

        // ⌘S on an untitled file routes through Save As: the panel appears…
        app.typeKey("s", modifierFlags: .command)
        let panel = savePanel(app)
        assertAppears(panel, timeout: 10, "⌘S should present the save panel")

        // …⌘⇧G steers it into the app container (the one place a sandboxed
        // relaunch can reopen without a panel), then the name + Return.
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(dir.path + "\n")
        app.typeKey("a", modifierFlags: .command)
        app.typeText(name + "\n")

        // Title updates, the dirty dot goes.
        waitForLabel(app.staticTexts["editor.title"], name, timeout: 10)
        waitForDisappearance(element(app, "editor.dirtyDot"))

        // The bytes on disk are a real SVG with the drawn rect.
        let svg = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(svg.contains("<svg"), "the saved file should be an SVG document")
        XCTAssertTrue(svg.contains("<rect"), "the saved file should contain the drawn rect")

        // Relaunch straight into the saved file: same title, one node.
        app.terminate()
        let relaunched = launchApp(arguments: ["--uitest-open", fileURL.path])
        waitForLabel(relaunched.staticTexts["editor.title"], name, timeout: 10)
        waitForLabel(nodeCount(relaunched), "1 nodes")
    }

    /// The save panel is powerbox-hosted: depending on the OS it surfaces
    /// as a sheet or a dialog in the app's hierarchy.
    private func savePanel(_ app: XCUIApplication) -> XCUIElement {
        if app.sheets.firstMatch.waitForExistence(timeout: 5) {
            return app.sheets.firstMatch
        }
        return app.dialogs.firstMatch
    }

    // MARK: - Journey D: workspace gallery over a fixture folder

    func testWorkspaceGalleryAndNewIcon() throws {
        // Two tiny SVGs in a category subfolder, written by the test.
        let workspace = try appScratchDirectory()
            .appendingPathComponent("ws-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let category = workspace.appendingPathComponent("Shapes", isDirectory: true)
        try FileManager.default.createDirectory(at: category, withIntermediateDirectories: true)
        try fixtureSVG("<rect x=\"4\" y=\"4\" width=\"16\" height=\"16\" fill=\"#222\"/>")
            .write(to: category.appendingPathComponent("alpha.svg"), atomically: true, encoding: .utf8)
        try fixtureSVG("<circle cx=\"12\" cy=\"12\" r=\"8\" fill=\"#933\"/>")
            .write(to: category.appendingPathComponent("beta.svg"), atomically: true, encoding: .utf8)

        let app = launchApp(arguments: ["--uitest-workspace", workspace.path])

        // The gallery shows the category header and both cells.
        assertAppears(app.buttons["gallery.section.Shapes"], timeout: 10)
        assertAppears(element(app, "gallery.cell.Shapes/alpha"))
        assertAppears(element(app, "gallery.cell.Shapes/beta"))

        // New Icon → name sheet (pre-filled, focused) → Return → editor.
        let newIcon = element(app, "gallery.newIcon")
        XCTAssertTrue(newIcon.exists, "the gallery header should offer New Icon")
        newIcon.click()
        assertAppears(app.textFields["newicon.name"], "the New Icon sheet should appear")
        app.typeKey(.return, modifierFlags: [])
        let back = element(app, "editor.back")
        assertAppears(back, "creating the icon should open it in the editor")
        XCTAssertEqual(back.label, "Gallery", "the editor's Back should lead to the gallery")

        // Back returns to the gallery (the created icon is now a cell too).
        back.click()
        assertAppears(element(app, "gallery.newIcon"), "Back should land on the gallery")
        assertAppears(element(app, "gallery.cell.Shapes/alpha"))
    }

    private func fixtureSVG(_ body: String) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\">\(body)</svg>"
    }
}
