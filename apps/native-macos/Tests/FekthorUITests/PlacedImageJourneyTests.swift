import AppKit
import XCTest

/// The placed-image journey: a pasted raster stays a raster on the canvas,
/// and right-click ▸ Vectorize traces it and swaps the vectors in for the
/// picture. One fresh app launch, driven through real events.
final class PlacedImageJourneyTests: FekthorUITestCase {

    /// ⌘N → ⌘V pastes a bitmap → one node, listed as an Image in Layers →
    /// right-click ▸ Vectorize… → the vectorizer traces it → Save → the
    /// editor is back and the status bar reports the swap.
    func testPasteImageThenVectorize() throws {
        putTestImageOnPasteboard()
        let app = launchApp()
        let window = app.windows.firstMatch
        openBlankEditor(app)
        waitForLabel(nodeCount(app), "0 nodes")

        // Paste: the raster lands as ONE node and stays a raster (the Layers
        // palette calls it an Image, not a Path).
        app.typeKey("v", modifierFlags: .command)
        waitForLabel(nodeCount(app), "1 nodes")
        assertAppears(app.staticTexts["Image"], "a pasted raster should stay an image layer")

        // Right-click the middle of the canvas — the image sits centred on
        // the artboard — and pick Vectorize.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        let vectorize = app.menuItems["Vectorize…"]
        assertAppears(vectorize, "right-clicking a placed image should offer Vectorize")
        vectorize.click()

        // The vectorizer opens on that image; Save enables when the trace
        // has a result.
        let save = element(app, "vectorize.save")
        assertAppears(save, timeout: 15, "the vectorizer's Save button should appear")
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "isEnabled == true"), object: save)
                ], timeout: 60),
            .completed, "the trace should finish and enable Save")
        save.click()

        // Back in the editor, with vectors where the image was.
        assertAppears(element(app, "tool.select"), timeout: 15, "Save should return to the editor")
        let status = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Vectorized")
        ).firstMatch
        assertAppears(status, timeout: 10, "the editor should report the image was vectorized")
        XCTAssertFalse(
            app.staticTexts["Image"].exists, "the image layer should be gone once vectorized")
    }

    /// Two solid squares on white: big enough to trace reliably, simple
    /// enough that tracing is instant.
    private func putTestImageOnPasteboard() {
        let size = NSSize(width: 96, height: 96)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.black.setFill()
        NSRect(x: 8, y: 8, width: 34, height: 80).fill()
        NSColor.red.setFill()
        NSRect(x: 54, y: 8, width: 34, height: 80).fill()
        image.unlockFocus()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
