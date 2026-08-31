import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Shared plumbing for the Slicer UI smoke suite. Every test launches its own
/// app process with `--uitest-open` / `--uitest-save` so the journey never has
/// to script an `NSOpenPanel`. Fixtures live inside the app's sandbox
/// container: the unsandboxed runner writes there freely, and it is the one
/// place the sandboxed app can read and write without a panel.
class SlicerUITestCase: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A scratch folder both processes can reach.
    ///
    /// The runner writes fixtures here; the sandboxed app can read them.
    func appScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("slicer-uitests/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// A source sheet with four distinct quadrants, written as a real PNG.
    @discardableResult
    func writeSheet(to url: URL, width: Int = 800, height: Int = 600) throws -> CGSize {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let colors = [
            CGColor(red: 0.9, green: 0.35, blue: 0.27, alpha: 1),
            CGColor(red: 0.27, green: 0.55, blue: 0.9, alpha: 1),
            CGColor(red: 0.94, green: 0.78, blue: 0.31, alpha: 1),
            CGColor(red: 0.35, green: 0.78, blue: 0.55, alpha: 1)
        ]
        let halfWidth = width / 2
        let halfHeight = height / 2
        let quadrants = [
            CGRect(x: 0, y: halfHeight, width: halfWidth, height: height - halfHeight),
            CGRect(x: halfWidth, y: halfHeight, width: width - halfWidth, height: height - halfHeight),
            CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight),
            CGRect(x: halfWidth, y: 0, width: width - halfWidth, height: halfHeight)
        ]
        for (color, rect) in zip(colors, quadrants) {
            context.setFillColor(color)
            context.fill(rect)
        }

        guard
            let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return CGSize(width: width, height: height)
    }

    /// A sheet of separated tiles on a white background — the shape gutter
    /// detection is meant to find.
    @discardableResult
    func writeTiledSheet(
        to url: URL,
        columns: Int = 3,
        rows: Int = 2,
        tile: Int = 120,
        gap: Int = 24
    ) throws -> CGSize {
        let width = columns * tile + (columns + 1) * gap
        let height = rows * tile + (rows + 1) * gap

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.15, green: 0.3, blue: 0.85, alpha: 1))
        for row in 0..<rows {
            for column in 0..<columns {
                context.fill(CGRect(
                    x: gap + column * (tile + gap),
                    y: gap + row * (tile + gap),
                    width: tile, height: tile
                ))
            }
        }

        guard
            let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            )
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return CGSize(width: width, height: height)
    }

    /// Three boxes that line up in no grid — the layout gutter projection
    /// cannot describe and element detection can.
    @discardableResult
    func writeCollage(to url: URL, width: Int = 600, height: Int = 400) throws -> CGSize {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 40, y: 240, width: 160, height: 120))
        context.fill(CGRect(x: 300, y: 180, width: 200, height: 160))
        context.fill(CGRect(x: 120, y: 40, width: 140, height: 100))

        guard
            let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            )
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return CGSize(width: width, height: height)
    }

    /// A save-folder name unique to this run. The app creates the folder in
    /// its own container, which outlives the process, so a shared name would
    /// let one run's output collide with the next one's.
    func uniqueSaveFolderName(_ prefix: String = "out") -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8))"
    }

    /// `saveFolderName` is a name, not a path: the app creates that folder in
    /// its own container. The runner cannot write into the app's sandbox (nor
    /// the app into the runner's), so the save half of the journey is verified
    /// through what the app reports it wrote.
    func launchApp(openImage: URL, saveFolderName: String) -> XCUIApplication {
        launchApp(openImages: [openImage], saveFolderName: saveFolderName)
    }

    /// `--uitest-open` may be repeated, which is how a test stands up a
    /// filmstrip with several images already in it.
    func launchApp(openImages: [URL], saveFolderName: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = openImages.flatMap { ["--uitest-open", $0.path] }
            + ["--uitest-save", saveFolderName]
        app.launch()
        return app
    }

    // MARK: - Queries

    func toolbarButton(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func exportSummary(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "slicer.exportSummary").firstMatch
    }

    func sliceCount(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "slicer.sliceCount").firstMatch
    }

    func slice(_ app: XCUIApplication, named name: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", name))
            .firstMatch
    }

    // MARK: - Waits

    func assertAppears(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        _ message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            message ?? "expected \(element) to appear within \(timeout)s",
            file: file, line: line)
    }

    /// SwiftUI exposes a `Text` string as label OR value depending on the
    /// macOS version — accept either.
    func waitForLabel(
        _ element: XCUIElement,
        _ label: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let done = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label == %@ OR value == %@", label, label),
                    object: element)
            ],
            timeout: timeout)
        let got = element.exists
            ? "label \"\(element.label)\" / value \"\(element.value ?? "")\"" : "<gone>"
        XCTAssertEqual(done, .completed, "expected \"\(label)\", got \(got)", file: file, line: line)
    }

    func waitForDisappearance(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let done = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
            ],
            timeout: timeout)
        XCTAssertEqual(done, .completed, "expected \(element) to disappear", file: file, line: line)
    }

    // MARK: - Canvas actions

    /// Drag on the canvas in window-normalised coordinates.
    func drag(_ window: XCUIElement, from: CGVector, to: CGVector) {
        window.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.2, thenDragTo: window.coordinate(withNormalizedOffset: to))
    }
}
