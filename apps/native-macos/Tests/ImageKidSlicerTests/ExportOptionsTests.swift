import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import ImageKidSlicer

final class ExportOptionsTests: XCTestCase {

    // MARK: - Format

    func testSameAsSourceKeepsTheSourceFormat() {
        let options = ExportOptions()
        let resolved = options.resolved(sourceType: .jpeg, sourceExtension: "jpeg")
        XCTAssertEqual(resolved.type, .jpeg)
        XCTAssertEqual(resolved.fileExtension, "jpeg")
    }

    func testAChosenFormatOverridesTheSource() {
        var options = ExportOptions()
        options.format = .png
        let resolved = options.resolved(sourceType: .jpeg, sourceExtension: "jpeg")
        XCTAssertEqual(resolved.type, .png)
        XCTAssertEqual(resolved.fileExtension, "png")
    }

    func testQualityOnlyAppliesToLossyFormats() {
        var options = ExportOptions()
        XCTAssertTrue(options.isLossy(sourceType: .jpeg), "same-as-source follows the source")
        XCTAssertFalse(options.isLossy(sourceType: .png))

        options.format = .jpeg
        XCTAssertTrue(options.isLossy(sourceType: .png), "an explicit JPEG is lossy whatever the source")

        options.format = .tiff
        XCTAssertFalse(options.isLossy(sourceType: .jpeg))
    }

    // MARK: - Scale

    func testUnscaledExportKeepsTheRegionSize() {
        let options = ExportOptions()
        XCTAssertFalse(options.needsResampling)
        XCTAssertEqual(
            options.outputPixelSize(for: CGRect(x: 0, y: 0, width: 300, height: 200)),
            CGSize(width: 300, height: 200)
        )
    }

    func testScaleIsAppliedAndRounded() {
        var options = ExportOptions()
        options.scalePercent = 50
        XCTAssertTrue(options.needsResampling)
        XCTAssertEqual(
            options.outputPixelSize(for: CGRect(x: 0, y: 0, width: 301, height: 200)),
            CGSize(width: 151, height: 100)
        )
    }

    func testScalingNeverProducesAnEmptyImage() {
        var options = ExportOptions()
        options.scalePercent = 10
        XCTAssertEqual(
            options.outputPixelSize(for: CGRect(x: 0, y: 0, width: 3, height: 3)),
            CGSize(width: 1, height: 1)
        )
    }

    // MARK: - Naming

    func testThePrefixIsSanitisedAndHyphenated() {
        var options = ExportOptions()
        options.namePrefix = "web/hero "
        XCTAssertEqual(options.sanitizedPrefix, "web-hero-")

        options.namePrefix = "   "
        XCTAssertEqual(options.sanitizedPrefix, "")
    }

    func testThePrefixLeadsBothAutomaticAndCustomNames() {
        XCTAssertEqual(
            SliceExporter.fileName(sourceName: "sheet", index: 0, count: 3, customName: nil, prefix: "web-"),
            "web-sheet-slice-01"
        )
        XCTAssertEqual(
            SliceExporter.fileName(sourceName: "sheet", index: 0, count: 3, customName: "hero", prefix: "web-"),
            "web-hero"
        )
    }

    func testSummaryDescribesWhatWillBeWritten() {
        var options = ExportOptions()
        XCTAssertEqual(options.summary(sourceType: .png, sourceExtension: "png"), "PNG")

        options.scalePercent = 200
        XCTAssertEqual(options.summary(sourceType: .png, sourceExtension: "png"), "PNG · 200%")

        options.format = .jpeg
        options.quality = 0.8
        XCTAssertEqual(options.summary(sourceType: .png, sourceExtension: "png"), "JPEG · 200% · q80")
    }

    // MARK: - Round trip through an export

    func testExportHonoursFormatScaleAndPrefix() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportOptionsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var options = ExportOptions()
        options.format = .png
        options.scalePercent = 50
        options.namePrefix = "web"

        let outcome = SliceExporter.export(SliceExportRequest(
            sourceName: "sheet",
            image: try TestImages.halves(width: 200, height: 100),
            sourceType: .jpeg,
            sourceExtension: "jpeg",
            slices: [Slice(rect: CGRect(x: 0, y: 0, width: 1, height: 1))],
            folder: folder,
            options: options
        ))

        XCTAssertTrue(outcome.isCompleteSuccess, "\(outcome.failures.map(\.message))")
        let url = try XCTUnwrap(outcome.created.first)
        XCTAssertEqual(url.lastPathComponent, "web-sheet-slice-01.png")

        let written = try TestImages.load(url)
        XCTAssertEqual(written.width, 100)
        XCTAssertEqual(written.height, 50)
    }

    func testScalingIsSkippedEntirelyAtOneHundredPercent() throws {
        let image = try TestImages.halves(width: 64, height: 32)
        XCTAssertTrue(try SliceImageIO.scaled(image, to: CGSize(width: 64, height: 32)) === image,
                      "an unscaled export should not pay for a redraw")
        XCTAssertTrue(try SliceImageIO.rendered(image, options: ExportOptions()) === image,
                      "and neither should the default options")
    }
}
