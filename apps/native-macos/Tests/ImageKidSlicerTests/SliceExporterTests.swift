import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ImageKidSlicer

final class SliceExporterTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageKidSlicerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
    }

    // MARK: - Naming

    func testDefaultNameIsZeroPaddedToTheSliceCount() {
        XCTAssertEqual(
            SliceExporter.fileName(sourceName: "sheet", index: 0, count: 3, customName: nil),
            "sheet-slice-01"
        )
        XCTAssertEqual(
            SliceExporter.fileName(sourceName: "sheet", index: 11, count: 120, customName: nil),
            "sheet-slice-012"
        )
    }

    func testCustomNameReplacesTheSliceNumber() {
        XCTAssertEqual(
            SliceExporter.fileName(sourceName: "sheet", index: 0, count: 3, customName: "hero"),
            "hero"
        )
    }

    func testPathSeparatorsAreStrippedFromNames() {
        XCTAssertEqual(SliceExporter.sanitized("icons/large"), "icons-large")
        XCTAssertEqual(SliceExporter.sanitized("   "), nil)
        XCTAssertEqual(SliceExporter.sanitized(nil), nil)
    }

    // MARK: - Collisions

    func testExistingFilesAreNeverOverwritten() throws {
        let taken = folder.appendingPathComponent("sheet-slice-01.png")
        FileManager.default.createFile(atPath: taken.path, contents: Data("original".utf8))

        let url = SliceExporter.uniqueURL(in: folder, baseName: "sheet-slice-01", fileExtension: "png")
        XCTAssertEqual(url.lastPathComponent, "sheet-slice-01-2.png")
        XCTAssertEqual(try String(contentsOf: taken, encoding: .utf8), "original")
    }

    func testTwoSlicesWithTheSameCustomNameDoNotCollide() {
        let first = SliceExporter.uniqueURL(in: folder, baseName: "hero", fileExtension: "png")
        let second = SliceExporter.uniqueURL(
            in: folder,
            baseName: "hero",
            fileExtension: "png",
            claimed: [first.path]
        )
        XCTAssertEqual(first.lastPathComponent, "hero.png")
        XCTAssertEqual(second.lastPathComponent, "hero-2.png")
    }

    // MARK: - Export

    func testExportWritesOneFilePerSliceInOrderAtSourceResolution() throws {
        let image = try TestImages.halves(width: 100, height: 100)
        let outcome = SliceExporter.export(SliceExportRequest(
            sourceName: "sheet",
            image: image,
            sourceType: .png,
            sourceExtension: "png",
            slices: [
                Slice(rect: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
                Slice(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
            ],
            folder: folder
        ))

        XCTAssertTrue(outcome.isCompleteSuccess)
        XCTAssertEqual(outcome.created.map(\.lastPathComponent), ["sheet-slice-01.png", "sheet-slice-02.png"])

        let left = try TestImages.load(outcome.created[0])
        let right = try TestImages.load(outcome.created[1])
        XCTAssertEqual(left.width, 50)
        XCTAssertEqual(left.height, 100)
        XCTAssertEqual(try TestImages.centrePixel(left).red, 255)
        XCTAssertEqual(try TestImages.centrePixel(right).blue, 255)
    }

    func testAlphaSurvivesAPNGExport() throws {
        let image = try TestImages.transparentLeftHalf(width: 80, height: 40)
        let outcome = SliceExporter.export(SliceExportRequest(
            sourceName: "sheet",
            image: image,
            sourceType: .png,
            sourceExtension: "png",
            slices: [Slice(rect: CGRect(x: 0, y: 0, width: 0.5, height: 1))],
            folder: folder
        ))

        XCTAssertTrue(outcome.isCompleteSuccess)
        let exported = try TestImages.load(try XCTUnwrap(outcome.created.first))
        XCTAssertNotEqual(exported.alphaInfo, .none)
        XCTAssertEqual(try TestImages.centrePixel(exported).alpha, 0)
    }

    func testOneBadSliceDoesNotAbortTheRest() throws {
        let image = try TestImages.halves(width: 100, height: 100)
        let outcome = SliceExporter.export(SliceExportRequest(
            sourceName: "sheet",
            image: image,
            sourceType: .png,
            sourceExtension: "png",
            slices: [
                Slice(rect: CGRect(x: 0, y: 0, width: 0.4, height: 0.4)),
                Slice(rect: CGRect(x: 0.5, y: 0.5, width: 0, height: 0.4)),
                Slice(rect: CGRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3))
            ],
            folder: folder
        ))

        XCTAssertEqual(outcome.created.count, 2)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertEqual(outcome.failures.first?.sliceName, "Slice 2")
        XCTAssertFalse(outcome.isCompleteSuccess)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("sheet-slice-02.png").path),
            "A failed slice must not leave a misleading file behind"
        )
    }

    func testExportDoesNotTouchTheSourceFile() throws {
        let source = folder.appendingPathComponent("sheet.png")
        try TestImages.write(TestImages.halves(width: 60, height: 60), as: .png, to: source)
        let before = try Data(contentsOf: source)

        let destination = folder.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        _ = SliceExporter.export(SliceExportRequest(
            sourceName: "sheet",
            image: try TestImages.load(source),
            sourceType: .png,
            sourceExtension: "png",
            slices: [Slice(rect: CGRect(x: 0, y: 0, width: 1, height: 1))],
            folder: destination
        ))

        XCTAssertEqual(try Data(contentsOf: source), before)
    }
}
