import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import ImageKidSlicer

/// Arrow-key nudging, copying a slice, and writing one out for a Finder drag.
@MainActor
final class SliceNudgeAndCopyTests: XCTestCase {
    private var suiteName: String!
    private var model: SlicerDocumentModel!
    private let sourceSize = CGSize(width: 200, height: 100)

    override func setUpWithError() throws {
        suiteName = "com.hakobs.imagekid.slicer.nudgetests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        model = SlicerDocumentModel(
            templates: SliceTemplateStore(store: defaults),
            exports: ExportOptionsStore(store: defaults)
        )
        let image = try TestImages.halves(width: Int(sourceSize.width), height: Int(sourceSize.height))
        model.adopt(SlicerDocumentModel.Source(
            url: URL(fileURLWithPath: "/tmp/sheet.png"),
            displayName: "sheet",
            image: image,
            preview: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
            outputType: .png,
            fileExtension: "png"
        ))
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        model = nil
        suiteName = nil
    }

    @discardableResult
    private func addSlice(_ rect: CGRect) -> Slice.ID {
        model.addSlice(rect)
        return model.slices.last!.id
    }

    // MARK: - Nudging

    func testNudgingMovesBySourcePixels() {
        addSlice(CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
        model.nudgeSelection(dx: 10, dy: 5)

        let pixels = model.slices[0].rect
        XCTAssertEqual(pixels.minX * sourceSize.width, 60, accuracy: 0.001, "50px + 10px")
        XCTAssertEqual(pixels.minY * sourceSize.height, 30, accuracy: 0.001, "25px + 5px")
    }

    func testNudgingNeverResizesOrLeavesTheImage() {
        addSlice(CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2))
        let size = model.slices[0].rect.size

        model.nudgeSelection(dx: 500, dy: 500)
        XCTAssertEqual(model.slices[0].rect.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(model.slices[0].rect.maxY, 1, accuracy: 0.0001)
        XCTAssertEqual(model.slices[0].rect.size, size)
    }

    func testALockedSliceIgnoresNudging() {
        let id = addSlice(CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
        model.setLocked(true, id: id)
        model.selectedSliceID = id

        model.nudgeSelection(dx: 10, dy: 10)
        XCTAssertEqual(model.slices[0].rect, CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
    }

    func testAGuideNudgesAlongItsOwnAxisOnly() {
        model.addGuide(axis: .vertical, at: 0.5)
        model.nudgeSelection(dx: 20, dy: 40)
        XCTAssertEqual(model.guides[0].position * sourceSize.width, 120, accuracy: 0.001)

        model.clearGuides()
        model.addGuide(axis: .horizontal, at: 0.5)
        model.nudgeSelection(dx: 20, dy: 40)
        XCTAssertEqual(model.guides[0].position * sourceSize.height, 90, accuracy: 0.001)
    }

    func testAGuideStopsAtTheImageEdge() {
        model.addGuide(axis: .vertical, at: 0.98)
        model.nudgeSelection(dx: 500, dy: 0)
        XCTAssertEqual(model.guides[0].position, 1, accuracy: 0.0001)
    }

    func testNudgingWithNothingSelectedDoesNothing() {
        addSlice(CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
        model.clearSelection()
        model.nudgeSelection(dx: 10, dy: 10)
        XCTAssertEqual(model.slices[0].rect, CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
    }

    // MARK: - Copying

    func testCopyingPutsTheSlicePixelsOnThePasteboard() throws {
        // The right half of the fixture is solid blue.
        addSlice(CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        XCTAssertTrue(model.canCopySelectedSlice)

        model.copySelectedSliceToClipboard()

        let image = try XCTUnwrap(NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cgImage.width, 100)
        XCTAssertEqual(cgImage.height, 100)
        XCTAssertEqual(try TestImages.centrePixel(cgImage).blue, 255)
    }

    func testCopyingNeedsASelection() {
        model.clearSelection()
        XCTAssertFalse(model.canCopySelectedSlice)
    }

    // MARK: - Dragging out

    func testDraggingOutWritesAFileNamedLikeTheExport() throws {
        let id = addSlice(CGRect(x: 0, y: 0, width: 0.5, height: 1))
        let url = try XCTUnwrap(model.temporaryFile(for: id))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.lastPathComponent, "sheet-slice-01.png")
        let written = try TestImages.load(url)
        XCTAssertEqual(written.width, 100)
        XCTAssertEqual(try TestImages.centrePixel(written).red, 255)
    }

    func testDraggingOutHonoursTheExportOptions() throws {
        model.exports.options.format = .jpeg
        model.exports.options.scalePercent = 50
        model.exports.options.namePrefix = "web"

        let id = addSlice(CGRect(x: 0, y: 0, width: 1, height: 1))
        let url = try XCTUnwrap(model.temporaryFile(for: id))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.lastPathComponent, "web-sheet-slice-01.jpeg")
        let written = try TestImages.load(url)
        XCTAssertEqual(written.width, 100)
        XCTAssertEqual(written.height, 50)
    }

    func testDraggingOutAnUnknownSliceProducesNothing() {
        XCTAssertNil(model.temporaryFile(for: UUID()))
    }
}
