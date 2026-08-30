import CoreGraphics
import XCTest
@testable import ImageKidSlicer

/// Gutter detection: finding the runs of background that separate tiles.
final class SliceDetectionTests: XCTestCase {

    // MARK: - Run finding

    func testACentralRunBecomesOneGuide() {
        // 10 wide: indices 4 and 5 are background.
        let flags = [false, false, false, false, true, true, false, false, false, false]
        XCTAssertEqual(SliceDetection.centres(ofRunsIn: flags, minimumRun: 2), [0.5])
    }

    func testRunsTouchingAnEdgeAreIgnoredAsMargin() {
        let flags = [true, true, false, false, true, true, false, false, true, true]
        // Only the middle run counts; the two at the edges are the sheet margin.
        XCTAssertEqual(SliceDetection.centres(ofRunsIn: flags, minimumRun: 2), [0.5])
    }

    func testRunsShorterThanTheMinimumAreNoise() {
        let flags = [false, false, false, true, false, false, false, false, false, false]
        XCTAssertTrue(SliceDetection.centres(ofRunsIn: flags, minimumRun: 2).isEmpty)
        XCTAssertEqual(SliceDetection.centres(ofRunsIn: flags, minimumRun: 1), [0.35])
    }

    func testSeveralGuttersEachGiveAGuide() {
        var flags = [Bool](repeating: false, count: 12)
        flags[3] = true; flags[4] = true
        flags[8] = true; flags[9] = true
        XCTAssertEqual(SliceDetection.centres(ofRunsIn: flags, minimumRun: 2), [4.0 / 12, 9.0 / 12])
    }

    func testAnAllBackgroundStripYieldsNothing() {
        XCTAssertTrue(SliceDetection.centres(ofRunsIn: [Bool](repeating: true, count: 10), minimumRun: 2).isEmpty)
    }

    func testTooFewColumnsYieldNothing() {
        XCTAssertTrue(SliceDetection.centres(ofRunsIn: [true, true], minimumRun: 1).isEmpty)
    }

    // MARK: - Whole images

    /// Tiles on a background, with gutters of `gap` between and around them.
    private func sheet(columns: Int, rows: Int, tile: Int, gap: Int) throws -> CGImage {
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
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
        for row in 0..<rows {
            for column in 0..<columns {
                context.fill(CGRect(
                    x: gap + column * (tile + gap),
                    y: gap + row * (tile + gap),
                    width: tile, height: tile
                ))
            }
        }
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    func testAThreeByTwoSheetSuggestsTheInteriorGutters() throws {
        let image = try sheet(columns: 3, rows: 2, tile: 60, gap: 10)
        let suggestion = SliceDetection.gutters(in: image)

        XCTAssertEqual(suggestion.vertical.count, 2, "three columns are separated by two gutters")
        XCTAssertEqual(suggestion.horizontal.count, 1, "two rows are separated by one gutter")

        // 3×60 + 4×10 = 220 wide; the gutters sit at 75 and 145.
        XCTAssertEqual(suggestion.vertical[0], 75.0 / 220, accuracy: 0.01)
        XCTAssertEqual(suggestion.vertical[1], 145.0 / 220, accuracy: 0.01)
    }

    func testTheSuggestedGuidesCutTheSheetIntoItsTiles() throws {
        let image = try sheet(columns: 3, rows: 2, tile: 60, gap: 10)
        let suggestion = SliceDetection.gutters(in: image)

        let rects = SliceAutoLayout.rects(
            verticalCuts: suggestion.vertical,
            horizontalCuts: suggestion.horizontal
        )
        XCTAssertEqual(rects.count, 6, "three columns by two rows")
    }

    func testASheetWithNoGuttersSuggestsNothing() throws {
        let image = try TestImages.halves(width: 120, height: 80)
        XCTAssertTrue(SliceDetection.gutters(in: image).isEmpty, "adjacent blocks have no background between them")
    }

    func testDetectionSurvivesADownscaledLargeSheet() throws {
        // Larger than the analysis cap, so it exercises the downsampling path.
        let image = try sheet(columns: 2, rows: 1, tile: 900, gap: 120)
        let suggestion = SliceDetection.gutters(in: image)
        XCTAssertEqual(suggestion.vertical.count, 1)
        XCTAssertEqual(suggestion.vertical[0], 0.5, accuracy: 0.02)
    }
}
