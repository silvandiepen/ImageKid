import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import ImageKidSlicer

/// Fixed output size: every file the same shape, whatever the slices measure.
final class ExportSizingTests: XCTestCase {

    // MARK: - Where the slice lands

    func testContainFitsTheWholeSliceAndCentresIt() {
        // A wide slice into a square: scaled to the width, letterboxed.
        let rect = ExportOptions.drawRect(
            for: CGSize(width: 100, height: 50),
            in: CGSize(width: 200, height: 200),
            fit: .contain
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 50, width: 200, height: 100))
    }

    func testCoverFillsTheOutputAndLetsTheRestFallOutside() {
        let rect = ExportOptions.drawRect(
            for: CGSize(width: 100, height: 50),
            in: CGSize(width: 200, height: 200),
            fit: .cover
        )
        XCTAssertEqual(rect, CGRect(x: -100, y: 0, width: 400, height: 200))
    }

    func testATallSliceIsHandledTheOtherWayRound() {
        let contain = ExportOptions.drawRect(
            for: CGSize(width: 50, height: 100),
            in: CGSize(width: 200, height: 200),
            fit: .contain
        )
        XCTAssertEqual(contain, CGRect(x: 50, y: 0, width: 100, height: 200))

        let cover = ExportOptions.drawRect(
            for: CGSize(width: 50, height: 100),
            in: CGSize(width: 200, height: 200),
            fit: .cover
        )
        XCTAssertEqual(cover, CGRect(x: 0, y: -100, width: 200, height: 400))
    }

    func testAMatchingShapeNeedsNoLetterboxingEitherWay() {
        for fit in ExportOptions.Fit.allCases {
            XCTAssertEqual(
                ExportOptions.drawRect(
                    for: CGSize(width: 50, height: 50),
                    in: CGSize(width: 200, height: 200),
                    fit: fit
                ),
                CGRect(x: 0, y: 0, width: 200, height: 200),
                "\(fit.label)")
        }
    }

    func testADegenerateSliceFallsBackToTheWholeOutput() {
        XCTAssertEqual(
            ExportOptions.drawRect(for: .zero, in: CGSize(width: 64, height: 64), fit: .contain),
            CGRect(x: 0, y: 0, width: 64, height: 64)
        )
    }

    // MARK: - The option itself

    func testFixedSizingIgnoresTheSliceSizeAndThePercentage() {
        var options = ExportOptions()
        options.sizing = .fixed
        options.outputWidth = 256
        options.outputHeight = 128
        options.scalePercent = 300

        XCTAssertEqual(
            options.outputPixelSize(for: CGRect(x: 0, y: 0, width: 37, height: 900)),
            CGSize(width: 256, height: 128)
        )
        XCTAssertTrue(options.needsResampling)
    }

    func testActualSizingStillFollowsTheSlice() {
        var options = ExportOptions()
        options.sizing = .actual
        XCTAssertFalse(options.needsResampling, "an unchanged export should not resample")
        XCTAssertEqual(
            options.outputPixelSize(for: CGRect(x: 0, y: 0, width: 37, height: 90)),
            CGSize(width: 37, height: 90)
        )
    }

    func testAnAbsurdOutputSizeIsClamped() {
        var options = ExportOptions()
        options.sizing = .fixed
        options.outputWidth = 0
        options.outputHeight = 99_999
        XCTAssertEqual(options.fixedSize.width, 1)
        XCTAssertEqual(options.fixedSize.height, CGFloat(ExportOptions.sizeRange.upperBound))
    }

    func testTheSummarySaysTheSizeAndTheFit() {
        var options = ExportOptions()
        options.sizing = .fixed
        options.outputWidth = 512
        options.outputHeight = 512
        options.fit = .cover
        XCTAssertEqual(options.summary(sourceType: .png, sourceExtension: "png"), "PNG · 512×512 cover")
    }

    // MARK: - Rendering

    private func render(_ source: CGSize, into options: ExportOptions) throws -> CGImage {
        let image = try TestImages.halves(width: Int(source.width), height: Int(source.height))
        return try SliceImageIO.rendered(image, options: options)
    }

    func testEveryOutputIsExactlyTheRequestedSize() throws {
        var options = ExportOptions()
        options.sizing = .fixed
        options.outputWidth = 200
        options.outputHeight = 200

        for fit in ExportOptions.Fit.allCases {
            options.fit = fit
            for source in [CGSize(width: 100, height: 50), CGSize(width: 40, height: 300), CGSize(width: 77, height: 77)] {
                let rendered = try render(source, into: options)
                XCTAssertEqual(rendered.width, 200, "\(fit.label) \(source)")
                XCTAssertEqual(rendered.height, 200, "\(fit.label) \(source)")
            }
        }
    }

    func testContainPadsWithTheChosenColour() throws {
        var options = ExportOptions()
        options.sizing = .fixed
        options.outputWidth = 200
        options.outputHeight = 200
        options.fit = .contain
        options.padding = .white

        // A wide slice leaves bands above and below.
        let rendered = try render(CGSize(width: 100, height: 20), into: options)
        let cropped = try XCTUnwrap(rendered.cropping(to: CGRect(x: 0, y: 0, width: 200, height: 20)))
        let corner = try TestImages.centrePixel(cropped)
        XCTAssertEqual(corner.red, 255)
        XCTAssertEqual(corner.green, 255)
        XCTAssertEqual(corner.blue, 255)
    }

    func testContainCanLeaveThePaddingClear() throws {
        var options = ExportOptions()
        options.sizing = .fixed
        options.outputWidth = 200
        options.outputHeight = 200
        options.fit = .contain
        options.padding = .transparent

        let rendered = try render(CGSize(width: 100, height: 20), into: options)
        let band = try XCTUnwrap(rendered.cropping(to: CGRect(x: 0, y: 0, width: 200, height: 20)))
        XCTAssertEqual(try TestImages.centrePixel(band).alpha, 0)
    }

    func testCoverLeavesNoPaddingAtAll() throws {
        var options = ExportOptions()
        options.sizing = .fixed
        options.outputWidth = 200
        options.outputHeight = 200
        options.fit = .cover
        options.padding = .white

        // The fixture is solid colour throughout, so every corner is content.
        let rendered = try render(CGSize(width: 100, height: 20), into: options)
        let band = try XCTUnwrap(rendered.cropping(to: CGRect(x: 0, y: 0, width: 200, height: 20)))
        XCTAssertEqual(try TestImages.centrePixel(band).alpha, 255)
        XCTAssertNotEqual(try TestImages.centrePixel(band).red, 255, "white here would mean padding")
    }

    // MARK: - Through a real export

    func testDifferentlyShapedSlicesAllComeOutTheSameSize() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportSizingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var options = ExportOptions()
        options.format = .png
        options.sizing = .fixed
        options.outputWidth = 128
        options.outputHeight = 128
        options.fit = .contain

        let outcome = SliceExporter.export(SliceExportRequest(
            sourceName: "sheet",
            image: try TestImages.halves(width: 400, height: 100),
            sourceType: .png,
            sourceExtension: "png",
            slices: [
                Slice(rect: CGRect(x: 0, y: 0, width: 0.1, height: 1)),      // tall
                Slice(rect: CGRect(x: 0.2, y: 0.4, width: 0.8, height: 0.2)) // wide
            ],
            folder: folder,
            options: options
        ))

        XCTAssertTrue(outcome.isCompleteSuccess, "\(outcome.failures.map(\.message))")
        for url in outcome.created {
            let written = try TestImages.load(url)
            XCTAssertEqual(written.width, 128, url.lastPathComponent)
            XCTAssertEqual(written.height, 128, url.lastPathComponent)
        }
    }

    // MARK: - Older files

    func testOptionsWrittenBeforeTheseSettingsExistedStillLoad() throws {
        let legacy = """
        {"format":"png","quality":0.8,"scalePercent":50,"namePrefix":"web"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ExportOptions.self, from: legacy)
        XCTAssertEqual(decoded.format, .png)
        XCTAssertEqual(decoded.scalePercent, 50)
        XCTAssertEqual(decoded.sizing, .actual, "the new setting takes its default")
        XCTAssertEqual(decoded.fit, .contain)
    }
}
