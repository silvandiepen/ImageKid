import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import ImageKidSlicer

/// The session document: what a saved slicing session records, and what comes
/// back when it is reopened.
@MainActor
final class SlicerSessionTests: XCTestCase {
    private var suiteName: String!
    private var model: SlicerDocumentModel!
    private var folder: URL!

    override func setUpWithError() throws {
        suiteName = "com.hakobs.imagekid.slicer.sessiontests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        model = SlicerDocumentModel(
            templates: SliceTemplateStore(store: defaults),
            exports: ExportOptionsStore(store: defaults),
            discardConfirmation: { _, _ in true }
        )
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlicerSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        if let folder { try? FileManager.default.removeItem(at: folder) }
        model = nil
        suiteName = nil
        folder = nil
    }

    @discardableResult
    private func open(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent("\(name).png")
        let image = try TestImages.halves(width: 200, height: 100)
        try TestImages.write(image, as: .png, to: url)
        model.append(SlicerDocumentModel.Source(
            url: url,
            displayName: name,
            image: image,
            preview: NSImage(cgImage: image, size: NSSize(width: 200, height: 100)),
            outputType: .png,
            fileExtension: "png"
        ))
        return url
    }

    // MARK: - What gets recorded

    func testTheDocumentRecordsEveryImageAndItsLayout() throws {
        try open("one")
        model.addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 1))
        model.rename(id: try XCTUnwrap(model.slices.first?.id), to: "hero")
        model.addGuide(axis: .vertical, at: 0.5)
        model.setCrop(CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4))
        try open("two")
        model.addSlice(CGRect(x: 0.5, y: 0, width: 0.5, height: 1))

        let document = model.sessionDocument
        XCTAssertEqual(document.version, SlicerSessionDocument.currentVersion)
        XCTAssertEqual(document.images.map(\.displayName), ["one", "two"])
        XCTAssertEqual(document.images[0].slices.first?.name, "hero")
        XCTAssertEqual(document.images[0].guides.first?.isVertical, true)
        XCTAssertNotNil(document.images[0].cropRect)
        XCTAssertNil(document.images[1].cropRect)
    }

    func testSettingsTravelWithTheSession() throws {
        try open("one")
        model.grid = SliceGrid(isEnabled: true, columns: 5, rows: 3)
        model.isSnappingEnabled = false
        model.snapsToCentreLines = false
        model.exports.options.format = .jpeg

        let document = model.sessionDocument
        XCTAssertEqual(document.grid.columns, 5)
        XCTAssertFalse(document.isSnappingEnabled)
        XCTAssertFalse(document.snapsToCentreLines)
        XCTAssertEqual(document.exportOptions.format, .jpeg)
    }

    // MARK: - Round trip

    func testTheDocumentSurvivesEncodingAndDecoding() throws {
        try open("one")
        model.addSlice(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        model.setLocked(true, id: try XCTUnwrap(model.slices.first?.id))
        model.addGuide(axis: .horizontal, at: 0.4)

        let original = model.sessionDocument
        let decoded = try SlicerSessionDocument.decoded(from: try original.encoded())
        XCTAssertEqual(decoded, original)
    }

    func testANewerFileVersionIsRefusedRatherThanMisread() throws {
        var document = SlicerSessionDocument()
        document.version = SlicerSessionDocument.currentVersion + 1
        XCTAssertThrowsError(try SlicerSessionDocument.decoded(from: try document.encoded()))
    }

    // MARK: - Restoring

    func testReopeningRestoresTheImagesAndTheirLayouts() async throws {
        try open("one")
        model.addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 1))
        model.rename(id: try XCTUnwrap(model.slices.first?.id), to: "hero")
        model.addGuide(axis: .vertical, at: 0.5)
        try open("two")
        model.addSlice(CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        model.grid = SliceGrid(isEnabled: true, columns: 4, rows: 2)

        let sessionURL = folder.appendingPathComponent("layout.slicer")
        try model.sessionDocument.encoded().write(to: sessionURL)

        // A fresh model, as if the app had been relaunched.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let reopened = SlicerDocumentModel(
            templates: SliceTemplateStore(store: defaults),
            exports: ExportOptionsStore(store: defaults)
        )
        reopened.openSession(at: sessionURL)

        let restored = expectation(description: "session restored")
        Task { @MainActor in
            for _ in 0..<200 where reopened.images.count < 2 {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            restored.fulfill()
        }
        await fulfillment(of: [restored], timeout: 10)

        XCTAssertEqual(reopened.images.count, 2)
        XCTAssertEqual(reopened.images.map(\.source.displayName), ["one", "two"])
        XCTAssertEqual(reopened.images[0].slices.first?.name, "hero")
        XCTAssertEqual(reopened.images[0].guides.count, 1)
        XCTAssertEqual(reopened.grid.columns, 4)
    }

    func testAMissingImageIsReportedRatherThanDroppedSilently() async throws {
        let url = try open("one")
        model.addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 1))

        var document = model.sessionDocument
        // Bookmarks are unavailable to an unsandboxed test runner, so the
        // stored path is the resolution route — point it at nothing.
        document.images[0].bookmark = nil
        document.images[0].path = url.deletingLastPathComponent()
            .appendingPathComponent("gone.png").path

        let sessionURL = folder.appendingPathComponent("broken.slicer")
        try document.encoded().write(to: sessionURL)

        model.openSession(at: sessionURL)

        let reported = expectation(description: "missing image reported")
        Task { @MainActor in
            for _ in 0..<200 where model.alert == nil {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            reported.fulfill()
        }
        await fulfillment(of: [reported], timeout: 10)

        XCTAssertEqual(model.alert?.title, "Nothing in that session could be opened")
    }

    func testCancellingSessionReplacementPreservesUnsavedWork() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let guarded = SlicerDocumentModel(
            templates: SliceTemplateStore(store: defaults),
            exports: ExportOptionsStore(store: defaults),
            discardConfirmation: { action, sessions in
                XCTAssertEqual(action, "Open Session")
                XCTAssertEqual(sessions.count, 1)
                return false
            }
        )
        let sourceURL = try open("replacement-source")
        let sourceImage = try TestImages.load(sourceURL)
        guarded.append(SlicerDocumentModel.Source(
            url: sourceURL,
            displayName: "keep-me",
            image: sourceImage,
            preview: NSImage(cgImage: sourceImage, size: NSSize(width: sourceImage.width, height: sourceImage.height)),
            outputType: .png,
            fileExtension: "png"
        ))
        guarded.addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 1))

        let sessionURL = folder.appendingPathComponent("replacement.slicer")
        try model.sessionDocument.encoded().write(to: sessionURL)
        guarded.openSession(at: sessionURL)

        XCTAssertEqual(guarded.images.map(\.source.displayName), ["keep-me"])
        XCTAssertEqual(guarded.slices.count, 1)
    }

    /// The identifier and extension have to match what project.yml declares
    /// in UTExportedTypeDeclarations, or a double-clicked session opens in
    /// something else. (Conformance is not asserted: an exported type is only
    /// registered from the *app's* Info.plist, not the test bundle's.)
    func testTheExportedTypeMatchesTheDeclarationInTheProject() throws {
        XCTAssertEqual(SlicerSessionDocument.fileExtension, "slicer")
        XCTAssertEqual(
            SlicerSessionDocument.contentType.identifier,
            "com.hakobs.imagekid.slicer.session"
        )

        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ImageKidSlicerTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // native-macos
            .appendingPathComponent("project.yml")
        let project = try String(contentsOf: projectURL, encoding: .utf8)
        XCTAssertTrue(
            project.contains("UTTypeIdentifier: com.hakobs.imagekid.slicer.session"),
            "the exported type must be declared in project.yml")
        XCTAssertTrue(project.contains("- slicer"), "with the slicer filename extension")
    }
}
