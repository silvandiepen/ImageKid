import CoreGraphics
import XCTest
@testable import ImageKidSlicer

/// Zooming about the pointer: the arithmetic that keeps what is being
/// inspected under the cursor while it grows.
final class SliceZoomTests: XCTestCase {
    private let pixelSize = CGSize(width: 400, height: 200)
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 800)

    private func layout(zoom: CGFloat = 1, pan: CGSize = .zero) -> SliceCanvasLayout {
        SliceCanvasLayout.make(pixelSize: pixelSize, bounds: bounds, zoom: zoom, pan: pan)
    }

    /// The property that matters: whatever the cursor is over does not move.
    private func assertAnchorHolds(
        anchor: CGPoint,
        factor: CGFloat,
        startZoom: CGFloat = 1,
        startPan: CGSize = .zero,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let before = layout(zoom: startZoom, pan: startPan)
        let unitBefore = before.normalizedPoint(anchor)

        let pan = before.panOffset(keeping: anchor, scaledBy: factor, in: bounds)
        let after = layout(zoom: startZoom * factor, pan: pan)
        let unitAfter = after.normalizedPoint(anchor)

        XCTAssertEqual(unitAfter.x, unitBefore.x, accuracy: 0.0005,
                       "the point under the cursor drifted horizontally", file: file, line: line)
        XCTAssertEqual(unitAfter.y, unitBefore.y, accuracy: 0.0005,
                       "the point under the cursor drifted vertically", file: file, line: line)
    }

    func testZoomingInHoldsThePointUnderTheCursor() {
        assertAnchorHolds(anchor: CGPoint(x: 200, y: 300), factor: 2)
    }

    func testZoomingOutHoldsItToo() {
        assertAnchorHolds(anchor: CGPoint(x: 600, y: 500), factor: 0.5, startZoom: 4)
    }

    func testItHoldsWhenAlreadyZoomedAndPanned() {
        assertAnchorHolds(
            anchor: CGPoint(x: 120, y: 640),
            factor: 1.25,
            startZoom: 3,
            startPan: CGSize(width: -80, height: 40)
        )
    }

    func testACornerHoldsAsWellAsTheCentre() {
        // Zooming about the centre would slide a corner away; this is the
        // whole reason for anchoring.
        assertAnchorHolds(anchor: CGPoint(x: 10, y: 210), factor: 3)
    }

    func testAnchoringAtTheCentreLeavesThePanAlone() {
        let pan = layout().panOffset(keeping: CGPoint(x: bounds.midX, y: bounds.midY), scaledBy: 2, in: bounds)
        XCTAssertEqual(pan.width, 0, accuracy: 0.0001)
        XCTAssertEqual(pan.height, 0, accuracy: 0.0001)
    }

    func testADegenerateLayoutOrFactorIsIgnored() {
        let unusable = SliceCanvasLayout.make(pixelSize: pixelSize, bounds: .zero, zoom: 1, pan: .zero)
        XCTAssertEqual(unusable.panOffset(keeping: .zero, scaledBy: 2, in: bounds), .zero)
        XCTAssertEqual(layout().panOffset(keeping: .zero, scaledBy: 0, in: bounds), .zero)
    }

    // MARK: - Keeping the image reachable

    func testPanIsClampedSoTheImageCannotBeFlungAway() {
        let imageSize = CGSize(width: 1600, height: 800)
        let clamped = SliceCanvasLayout.clampedPan(
            CGSize(width: 99_999, height: -99_999),
            imageSize: imageSize,
            bounds: bounds
        )
        // Half the canvas plus half the image, less the margin kept on screen.
        XCTAssertEqual(clamped.width, 800 / 2 + 1600 / 2 - 60, accuracy: 0.001)
        XCTAssertEqual(clamped.height, -(800 / 2 + 800 / 2 - 60), accuracy: 0.001)
    }

    func testAModestPanIsLeftAlone() {
        let pan = CGSize(width: 40, height: -25)
        XCTAssertEqual(
            SliceCanvasLayout.clampedPan(pan, imageSize: CGSize(width: 800, height: 400), bounds: bounds),
            pan
        )
    }

    // MARK: - Range

    @MainActor
    func testZoomStopsAtFitAndAtTheDetailLimit() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "zoom-\(UUID().uuidString)"))
        let model = SlicerDocumentModel(
            templates: SliceTemplateStore(store: suite),
            exports: ExportOptionsStore(store: suite)
        )
        let image = try TestImages.halves(width: 200, height: 100)
        model.adopt(SlicerDocumentModel.Source(
            url: nil, displayName: "s", image: image,
            preview: .init(cgImage: image, size: .init(width: 200, height: 100)),
            outputType: .png, fileExtension: "png"
        ))

        model.setZoom(0.1)
        XCTAssertEqual(model.zoom, SlicerDocumentModel.minimumZoom, "fit is as far out as it goes")

        model.setZoom(1000)
        XCTAssertEqual(model.zoom, SlicerDocumentModel.maximumZoom)
        XCTAssertGreaterThanOrEqual(SlicerDocumentModel.maximumZoom, 32, "far enough in to see source pixels")
    }
}
