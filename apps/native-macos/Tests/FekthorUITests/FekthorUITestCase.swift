import XCTest

/// Shared plumbing for the Fekthor UI smoke suite: every test launches its
/// own fresh app in the deterministic `--uitest` environment (wiped defaults
/// suite — default panel layout, no recents; see UITestSupport.swift in the
/// app) and drives it through real events. Fixtures live inside the app's
/// sandbox container so both sides can touch them: the unsandboxed test
/// runner writes there freely, and the container is the one place the
/// sandboxed app can always read without an open panel.
class FekthorUITestCase: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A fresh app process in the deterministic UI-test environment.
    func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"] + arguments
        app.launch()
        return app
    }

    // MARK: - Fixtures (inside the app container)

    private static let containerData = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.hakobs.fekthor/Data", isDirectory: true)

    /// A scratch folder the sandboxed app can read and write: the app
    /// container's tmp. If the container has never been created on this
    /// machine, one throwaway launch makes the system set it up properly
    /// (creating the folder tree by hand would fight containermanagerd).
    func appScratchDirectory() throws -> URL {
        if !FileManager.default.fileExists(atPath: Self.containerData.path) {
            let app = launchApp()
            _ = app.windows.firstMatch.waitForExistence(timeout: 15)
            app.terminate()
        }
        let dir = Self.containerData.appendingPathComponent(
            "tmp/fekthor-uitests", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Queries

    /// The element carrying an accessibilityIdentifier, whatever its role
    /// (SwiftUI identifiers can land on buttons, texts or plain groups).
    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The editor status bar's "<n> nodes" readout.
    func nodeCount(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["editor.nodeCount"]
    }

    // MARK: - Waits

    /// Existence with the suite's standard timeout, as an assertion.
    func assertAppears(
        _ element: XCUIElement, timeout: TimeInterval = 5,
        _ message: String? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            message ?? "expected \(element) to appear within \(timeout)s",
            file: file, line: line)
    }

    /// Waits until the element's label matches exactly (e.g. the node-count
    /// text flipping from "0 nodes" to "1 nodes").
    func waitForLabel(
        _ element: XCUIElement, _ label: String, timeout: TimeInterval = 5,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let done = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label == %@", label), object: element)
            ],
            timeout: timeout)
        XCTAssertEqual(
            done, .completed,
            "expected label \"\(label)\", got \"\(element.exists ? element.label : "<gone>")\"",
            file: file, line: line)
    }

    /// Waits until the element no longer exists.
    func waitForDisappearance(
        _ element: XCUIElement, timeout: TimeInterval = 5,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let done = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"), object: element)
            ],
            timeout: timeout)
        XCTAssertEqual(done, .completed, "expected \(element) to disappear", file: file, line: line)
    }

    // MARK: - Editor actions

    /// Home → ⌘N → the editor with its tool shelf on screen.
    func openBlankEditor(_ app: XCUIApplication) {
        // Match the card by identifier, not its text: SwiftUI sometimes
        // exposes the label combined into the button (no child StaticText).
        assertAppears(
            element(app, "home.newFile"), timeout: 10, "home should show the New File card")
        app.typeKey("n", modifierFlags: .command)
        assertAppears(element(app, "tool.select"), "the editor tool shelf should appear after ⌘N")
    }

    /// Normalized window spots for canvas drags: safely inside the free
    /// canvas area — clear of the default palettes (Layers left, Fill/Stroke
    /// right), the zoom pill top-centre and the tool shelf bottom-centre.
    static let drawFrom = CGVector(dx: 0.42, dy: 0.38)
    static let drawTo = CGVector(dx: 0.54, dy: 0.58)

    /// Drags out a shape with the current drawing tool.
    func dragOnCanvas(
        _ window: XCUIElement,
        from: CGVector = FekthorUITestCase.drawFrom,
        to: CGVector = FekthorUITestCase.drawTo
    ) {
        window.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.2, thenDragTo: window.coordinate(withNormalizedOffset: to))
    }

    /// Press M and drag one rectangle out on the canvas of a fresh editor;
    /// asserts the node count reflects it.
    func drawRect(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        waitForLabel(nodeCount(app), "0 nodes")
        app.typeKey("m", modifierFlags: [])
        dragOnCanvas(window)
        waitForLabel(nodeCount(app), "1 nodes")
    }
}
