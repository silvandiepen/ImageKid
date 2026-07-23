import XCTest

/// Shared plumbing for the smoke suite: launch modes, identifier-first element
/// lookup, polling waits, and canvas coordinates. Every test launches a fresh
/// app (wiped defaults via `--uitest`) and asserts against accessibility
/// identifiers and values — never pixels.
class ImageKidUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// Launches a fresh app. `withImage` opens a generated sample picture
    /// straight into the editor (`--uitest-image`), bypassing the photo picker.
    func launch(withImage: Bool) {
        app = XCUIApplication()
        app.launchArguments = withImage ? ["--uitest", "--uitest-image"] : ["--uitest"]
        app.launch()
        // Let the first layout settle before the first synthesized event, so
        // taps never resolve frames captured mid-appearance.
        waitFor(withImage ? "editor.toolbar" : "editor.emptyState", timeout: 15)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.75))
    }

    /// Taps a bottom-toolbar tool and verifies it actually became the active
    /// tool (`isSelected`). Synthesized taps on the simulator can drift a
    /// couple of dozen points to the right near the bottom of the screen
    /// (enough to hit the 45pt-pitch neighbour), so on a mis-tap this nudges
    /// the tap point left and tries again — tapping the right button also
    /// switches away from any accidentally activated neighbour.
    func activateTool(
        _ id: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no tool button \(id)", file: file, line: line)
        for nudge: CGFloat in [0, -12, -18, -25, -32] {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: nudge, dy: 0))
                .tap()
            if poll(timeout: 2, { button.isSelected }) { return }
        }
        XCTFail("\(id) never became the active tool", file: file, line: line)
    }

    // MARK: Identifier-first lookup

    /// Matches any element type, so identifiers can move between views
    /// (buttons, containers, shapes) without breaking queries.
    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func count(_ id: String) -> Int {
        app.descendants(matching: .any).matching(identifier: id).count
    }

    @discardableResult
    func waitFor(
        _ id: String, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let found = element(id)
        XCTAssertTrue(
            found.waitForExistence(timeout: timeout),
            "Timed out waiting for \(id)", file: file, line: line)
        return found
    }

    func waitGone(
        _ id: String, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            poll(timeout: timeout) { !self.element(id).exists },
            "\(id) is still present", file: file, line: line)
    }

    /// Polls a condition for label/value/frame changes, which have no
    /// exists-based expectation to wait on.
    func poll(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        }
        return condition()
    }

    // MARK: Canvas

    /// The inline editing canvas (present while an editing tool is active).
    var canvas: XCUIElement { element("editor.canvas") }

    func canvasPoint(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate {
        canvas.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
    }

    func tapCanvas(_ dx: CGFloat, _ dy: CGFloat) {
        canvasPoint(dx, dy).tap()
    }

    func dragOnCanvas(from: (dx: CGFloat, dy: CGFloat), to: (dx: CGFloat, dy: CGFloat)) {
        canvasPoint(from.dx, from.dy).press(
            forDuration: 0.15,
            thenDragTo: canvasPoint(to.dx, to.dy),
            withVelocity: .slow,
            thenHoldForDuration: 0.1)
    }

    /// Waits until the inline text editor actually has keyboard focus, so
    /// `typeText` never races the async focus grab.
    func waitForKeyboardFocus(
        on field: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            poll { (field.value(forKey: "hasKeyboardFocus") as? Bool) == true },
            "text field never received keyboard focus", file: file, line: line)
    }
}
