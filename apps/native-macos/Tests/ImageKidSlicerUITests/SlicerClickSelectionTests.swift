import XCTest

/// Clicking a slice has to select *that* slice — not merely leave whatever was
/// selected before. The delete-based journeys cannot tell the difference,
/// because the count drops by one either way.
final class SlicerClickSelectionTests: SlicerUITestCase {

    func testClickingASliceAfterDetectionSelectsThatSlice() throws {
        let scratch = try appScratchDirectory()
        let collage = scratch.appendingPathComponent("collage.png")
        try writeCollage(to: collage)

        let app = launchApp(openImage: collage, saveFolderName: uniqueSaveFolderName("sel"))
        assertAppears(app.windows.firstMatch, timeout: 20)

        toolbarButton(app, "slicer.detectElements").click()
        waitForLabel(sliceCount(app), "3 slices")

        // Remember what the middle slice is, by its own reported geometry.
        let second = slice(app, named: "Slice 2")
        assertAppears(second)
        let secondGeometry = try XCTUnwrap(second.value as? String)

        // Click it, then delete. If the click selected it, it is the one that
        // goes; if the click did nothing, some other slice goes instead.
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
        waitForLabel(sliceCount(app), "2 slices")

        let remaining = ["Slice 1", "Slice 2"].compactMap { slice(app, named: $0).value as? String }
        XCTAssertEqual(remaining.count, 2)
        XCTAssertFalse(
            remaining.contains(secondGeometry),
            "the clicked slice is still there, so the click did not select it")
    }

    /// The likely real report: Suggest Guides leaves you on the Guides tool,
    /// so the next click lays down a guide instead of selecting the slice
    /// under the pointer. Producing slices should put you where you can edit
    /// them.
    func testDetectingElementsLeavesYouAbleToSelectThem() throws {
        let scratch = try appScratchDirectory()
        let collage = scratch.appendingPathComponent("collage.png")
        try writeCollage(to: collage)

        let app = launchApp(openImage: collage, saveFolderName: uniqueSaveFolderName("sel"))
        assertAppears(app.windows.firstMatch, timeout: 20)

        // Arrive holding the Guides tool, as anyone exploring the bar would.
        toolbarButton(app, "slicer.tool.guides").click()
        toolbarButton(app, "slicer.detectElements").click()
        waitForLabel(sliceCount(app), "3 slices")

        let second = slice(app, named: "Slice 2")
        assertAppears(second)
        let geometry = try XCTUnwrap(second.value as? String)

        second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])

        waitForLabel(sliceCount(app), "2 slices")
        let remaining = ["Slice 1", "Slice 2"].compactMap { slice(app, named: $0).value as? String }
        XCTAssertFalse(remaining.contains(geometry), "the click did not select the slice under it")
    }

    func testAClickedSliceCanThenBeNudged() throws {
        let scratch = try appScratchDirectory()
        let collage = scratch.appendingPathComponent("collage.png")
        try writeCollage(to: collage)

        let app = launchApp(openImage: collage, saveFolderName: uniqueSaveFolderName("sel"))
        assertAppears(app.windows.firstMatch, timeout: 20)

        toolbarButton(app, "slicer.detectElements").click()
        waitForLabel(sliceCount(app), "3 slices")

        let third = slice(app, named: "Slice 3")
        assertAppears(third)
        let before = try XCTUnwrap(third.value as? String)

        third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        app.typeKey(.rightArrow, modifierFlags: [])

        let after = try XCTUnwrap(slice(app, named: "Slice 3").value as? String)
        XCTAssertNotEqual(before, after, "the clicked slice should be the one the arrow key moves")
    }
}
