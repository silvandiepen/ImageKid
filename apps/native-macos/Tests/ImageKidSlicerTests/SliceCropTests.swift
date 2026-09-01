import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import ImageKidSlicer

/// The Crop tool: one region, saved straight out as a single file.
@MainActor
final class SliceCropTests: XCTestCase {
    private var suiteName: String!
    private var model: SlicerDocumentModel!
    private var folder: URL!

    private let sourceSize = CGSize(width: 200, height: 100)

    override func setUpWithError() throws {
        suiteName = "com.hakobs.imagekid.slicer.croptests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        model = SlicerDocumentModel(templates: SliceTemplateStore(store: defaults))

        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageKidSlicerCropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        if let folder { try? FileManager.default.removeItem(at: folder) }
        model = nil
        suiteName = nil
        folder = nil
    }

    private func loadSource() throws {
        let image = try TestImages.halves(width: Int(sourceSize.width), height: Int(sourceSize.height))
        model.adopt(SlicerDocumentModel.Source(
            url: folder.appendingPathComponent("sheet.png"),
            displayName: "sheet",
            image: image,
            preview: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
            outputType: .png,
            fileExtension: "png"
        ))
    }

    // MARK: - Region

    func testEnteringCropStartsFromTheWholeImage() throws {
        try loadSource()
        XCTAssertNil(model.cropRect)

        model.prepareCropIfNeeded()
        XCTAssertEqual(model.cropRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(model.cropPixelRect, CGRect(origin: .zero, size: sourceSize))
    }

    func testEnteringCropAgainKeepsTheRegionAlreadyDrawn() throws {
        try loadSource()
        model.setCrop(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))

        model.prepareCropIfNeeded()
        XCTAssertEqual(model.cropRect, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    func testCropIsClampedToTheImage() throws {
        try loadSource()
        model.setCrop(CGRect(x: -0.5, y: 0.5, width: 2, height: 2))
        XCTAssertEqual(model.cropRect, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testResetReturnsTheWholeImage() throws {
        try loadSource()
        model.setCrop(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        model.resetCrop()
        XCTAssertEqual(model.cropRect, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testWithoutASourceThereIsNothingToCrop() {
        model.prepareCropIfNeeded()
        XCTAssertNil(model.cropRect)
        XCTAssertNil(model.cropPixelRect)
        XCTAssertFalse(model.canCropAndSave)
    }

    func testANewSourceDropsTheOldCrop() throws {
        try loadSource()
        model.setCrop(CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4))
        XCTAssertTrue(model.canCropAndSave)

        try loadSource()
        XCTAssertNil(model.cropRect)
    }

    func testCropIsIndependentOfTheSlices() throws {
        try loadSource()
        model.addSlice(CGRect(x: 0, y: 0, width: 0.3, height: 0.3))
        model.setCrop(CGRect(x: 0.5, y: 0, width: 0.5, height: 1))

        model.replaceSlices(with: SliceAutoLayout.rects(verticalCuts: [0.5], horizontalCuts: []))
        XCTAssertEqual(model.cropRect, CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
    }

    // MARK: - Export

    func testExportWritesTheCroppedRegionAtSourceResolution() throws {
        let image = try TestImages.halves(width: 200, height: 100)
        let url = folder.appendingPathComponent("sheet-crop.png")

        // The right half of the fixture is solid blue.
        try SliceExporter.exportCrop(
            image,
            rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
            outputType: .png,
            to: url
        )

        let written = try TestImages.load(url)
        XCTAssertEqual(written.width, 100)
        XCTAssertEqual(written.height, 100)
        XCTAssertEqual(try TestImages.centrePixel(written).blue, 255)
    }

    func testExportRejectsAnEmptyRegion() throws {
        let image = try TestImages.halves(width: 200, height: 100)
        XCTAssertThrowsError(
            try SliceExporter.exportCrop(
                image,
                rect: CGRect(x: 0.5, y: 0.5, width: 0, height: 0.2),
                outputType: .png,
                to: folder.appendingPathComponent("empty.png")
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("empty.png").path))
    }

    func testExportIsAtomicAndLeavesNoTemporaryFile() throws {
        let image = try TestImages.halves(width: 60, height: 60)
        try SliceExporter.exportCrop(
            image,
            rect: CGRect(x: 0, y: 0, width: 1, height: 1),
            outputType: .png,
            to: folder.appendingPathComponent("full.png")
        )
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(".") }
        XCTAssertTrue(leftovers.isEmpty, "found \(leftovers)")
    }
}
