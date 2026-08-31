import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import ImageKidSlicer

/// Sticking to what is actually in the image, and Option-dragging a copy out.
@MainActor
final class SliceContentSnapTests: XCTestCase {
    private var suiteName: String!
    private var model: SlicerDocumentModel!

    override func setUpWithError() throws {
        suiteName = "com.hakobs.imagekid.slicer.contenttests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        model = SlicerDocumentModel(
            templates: SliceTemplateStore(store: defaults),
            exports: ExportOptionsStore(store: defaults)
        )
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        model = nil
        suiteName = nil
    }

    /// Tiles on a background, with a gap between and around them.
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
                    x: gap + column * (tile + gap), y: gap + row * (tile + gap),
                    width: tile, height: tile
                ))
            }
        }
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    // MARK: - Finding the edges

    func testContentEdgesAreTheBordersOfEachRunOfContent() {
        // Background, then content at 3…5, then background.
        let flags = [true, true, true, false, false, false, true, true, true, true]
        XCTAssertEqual(
            SliceDetection.edges(ofContentIn: flags, minimumRun: 2),
            [0.3, 0.6]
        )
    }

    func testContentTouchingTheImageEdgeContributesOnlyItsInnerBorder() {
        let flags = [false, false, false, true, true, true, true, true, true, true]
        XCTAssertEqual(
            SliceDetection.edges(ofContentIn: flags, minimumRun: 2),
            [0.3],
            "the outer border is the image edge, which is already a target")
    }

    func testShortSpecksAreNotContent() {
        let flags = [true, true, false, true, true, true, true, true, true, true]
        XCTAssertTrue(SliceDetection.edges(ofContentIn: flags, minimumRun: 2).isEmpty)
    }

    func testAThreeByTwoSheetGivesTheBorderOfEveryTile() throws {
        let image = try sheet(columns: 3, rows: 2, tile: 60, gap: 10)
        let edges = SliceDetection.contentEdges(in: image)

        // 220 wide: tiles span 10–70, 80–140, 150–210 → six vertical borders.
        XCTAssertEqual(edges.vertical.count, 6)
        XCTAssertEqual(edges.vertical[0], 10.0 / 220, accuracy: 0.01)
        XCTAssertEqual(edges.vertical[1], 70.0 / 220, accuracy: 0.01)
        // 140 tall: tiles span 10–70 and 80–140 → four horizontal borders.
        XCTAssertEqual(edges.horizontal.count, 4)
    }

    func testGuttersAndContentEdgesDescribeDifferentLines() throws {
        let image = try sheet(columns: 2, rows: 1, tile: 60, gap: 20)
        let gutters = SliceDetection.gutters(in: image)
        let edges = SliceDetection.contentEdges(in: image)

        // 2×60 + 3×20 = 180 wide. The gutter runs 80–100, centre 90; the two
        // tiles border at 20, 80, 100 and 160.
        XCTAssertEqual(gutters.vertical, [90.0 / 180])
        XCTAssertEqual(edges.vertical.map { ($0 * 180).rounded() }, [20, 80, 100, 160])
    }

    // MARK: - Snapping to them

    func testADraggedEdgeSticksToTheBorderOfATile() throws {
        let image = try sheet(columns: 2, rows: 1, tile: 60, gap: 20)
        let edges = SliceDetection.contentEdges(in: image)

        let targets = SliceSnapping.targets(
            slices: [], excluding: nil, guides: [], grid: SliceGrid(),
            includeCentreLines: false, contentEdges: edges
        )

        // Pulled to just short of the second tile's left border at 100/180.
        let result = SliceSnapping.snapEdges(
            CGRect(x: 0.1, y: 0, width: 0.45, height: 1),
            movingLeft: false, movingRight: true, movingTop: false, movingBottom: false,
            targets: targets, thresholdX: 0.02, thresholdY: 0.02
        )
        XCTAssertEqual(result.rect.maxX, 100.0 / 180, accuracy: 0.001)
        XCTAssertEqual(result.rect.minX, 0.1, accuracy: 0.0001, "the anchored edge stays put")
    }

    func testContentEdgesCanBeLeftOut() throws {
        let image = try sheet(columns: 2, rows: 1, tile: 60, gap: 20)
        let withEdges = SliceSnapping.targets(
            slices: [], excluding: nil, guides: [], grid: SliceGrid(),
            includeCentreLines: false, contentEdges: SliceDetection.contentEdges(in: image)
        )
        let without = SliceSnapping.targets(
            slices: [], excluding: nil, guides: [], grid: SliceGrid(),
            includeCentreLines: false, contentEdges: nil
        )
        XCTAssertGreaterThan(withEdges.vertical.count, without.vertical.count)
        XCTAssertEqual(without.vertical.sorted(), [0, 1])
    }

    func testASourceScansItsContentEdgesWhenItLoads() throws {
        let image = try sheet(columns: 3, rows: 2, tile: 60, gap: 10)
        model.adopt(SlicerDocumentModel.Source(
            url: nil,
            displayName: "tiles",
            image: image,
            preview: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
            outputType: .png,
            fileExtension: "png",
            contentEdges: SliceDetection.contentEdges(in: image)
        ))
        XCTAssertEqual(model.source?.contentEdges.vertical.count, 6)
    }

    // MARK: - Option-drag

    func testDuplicatingWithNoOffsetLeavesTheCopyOnTopOfTheOriginal() {
        model.adopt(makeBlankSource())
        model.addSlice(CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3))
        let original = model.slices[0]

        let copy = model.duplicate(id: original.id, offset: 0)

        XCTAssertEqual(model.slices.count, 2)
        XCTAssertEqual(model.slices[1].rect, original.rect, "same place, same dimensions")
        XCTAssertEqual(model.selectedSliceID, copy, "the copy is what the drag will move")
        XCTAssertEqual(model.slices[0].rect, original.rect, "the original does not move")
    }

    func testTheOrdinaryDuplicateStillOffsetsSoItIsVisible() {
        model.adopt(makeBlankSource())
        model.addSlice(CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3))
        model.duplicateSelectedSlice()

        XCTAssertEqual(model.slices.count, 2)
        XCTAssertNotEqual(model.slices[1].rect.origin, model.slices[0].rect.origin)
        XCTAssertEqual(model.slices[1].rect.size, model.slices[0].rect.size)
    }

    func testACopyIsNeverBornLockedOrNamed() {
        model.adopt(makeBlankSource())
        model.addSlice(CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3))
        let id = model.slices[0].id
        model.rename(id: id, to: "hero")
        model.setLocked(true, id: id)

        let copy = model.duplicate(id: id, offset: 0)
        XCTAssertNotNil(copy)
        XCTAssertFalse(model.slices[1].isLocked)
        XCTAssertNil(model.slices[1].name, "a copy takes the next automatic name")
    }

    func testDuplicatingAnUnknownSliceDoesNothing() {
        model.adopt(makeBlankSource())
        XCTAssertNil(model.duplicate(id: UUID()))
        XCTAssertTrue(model.slices.isEmpty)
    }

    private func makeBlankSource() -> SlicerDocumentModel.Source {
        let image = try! TestImages.halves(width: 200, height: 100)
        return SlicerDocumentModel.Source(
            url: nil,
            displayName: "sheet",
            image: image,
            preview: NSImage(cgImage: image, size: NSSize(width: 200, height: 100)),
            outputType: .png,
            fileExtension: "png"
        )
    }
}
