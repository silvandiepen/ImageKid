import CoreGraphics
import XCTest
@testable import ImageKidSlicer

final class SliceCanvasLayoutTests: XCTestCase {
    private let pixelSize = CGSize(width: 400, height: 200)
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 800)

    func testImageIsAspectFittedAndCentred() {
        let layout = SliceCanvasLayout.make(pixelSize: pixelSize, bounds: bounds, zoom: 1, pan: .zero)
        XCTAssertEqual(layout.imageRect, CGRect(x: 0, y: 200, width: 800, height: 400))
    }

    func testZoomAndPanNeverChangeSourceRelativeGeometry() {
        // The same canvas point must map to the same normalised coordinate
        // regardless of view transform — this is the guarantee the exported
        // crop depends on.
        let normalized = CGRect(x: 0.25, y: 0.5, width: 0.25, height: 0.25)

        for (zoom, pan) in [(CGFloat(1), CGSize.zero), (2.5, CGSize(width: 40, height: -90)), (7, CGSize(width: -200, height: 15))] {
            let layout = SliceCanvasLayout.make(pixelSize: pixelSize, bounds: bounds, zoom: zoom, pan: pan)
            let viewRect = layout.viewRect(for: normalized)
            let roundTrip = SliceGeometry.rect(
                from: layout.normalizedPoint(CGPoint(x: viewRect.minX, y: viewRect.minY)),
                to: layout.normalizedPoint(CGPoint(x: viewRect.maxX, y: viewRect.maxY))
            )
            XCTAssertEqual(roundTrip.minX, normalized.minX, accuracy: 0.0001)
            XCTAssertEqual(roundTrip.minY, normalized.minY, accuracy: 0.0001)
            XCTAssertEqual(roundTrip.width, normalized.width, accuracy: 0.0001)
            XCTAssertEqual(roundTrip.height, normalized.height, accuracy: 0.0001)
        }
    }

    func testDragTranslationScalesWithZoom() {
        let unzoomed = SliceCanvasLayout.make(pixelSize: pixelSize, bounds: bounds, zoom: 1, pan: .zero)
        let zoomed = SliceCanvasLayout.make(pixelSize: pixelSize, bounds: bounds, zoom: 4, pan: .zero)
        let translation = CGSize(width: 80, height: 0)
        XCTAssertEqual(
            unzoomed.normalizedDelta(translation).width,
            zoomed.normalizedDelta(translation).width * 4,
            accuracy: 0.0001
        )
    }

    func testCornerHandlesWinOverEdgeHandles() {
        let layout = SliceCanvasLayout.make(pixelSize: pixelSize, bounds: bounds, zoom: 1, pan: .zero)
        let rect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let viewRect = layout.viewRect(for: rect)

        XCTAssertEqual(layout.handle(at: CGPoint(x: viewRect.minX, y: viewRect.minY), of: rect, tolerance: 10), .topLeft)
        XCTAssertEqual(layout.handle(at: CGPoint(x: viewRect.midX, y: viewRect.maxY), of: rect, tolerance: 10), .bottom)
        XCTAssertNil(layout.handle(at: CGPoint(x: viewRect.midX, y: viewRect.midY), of: rect, tolerance: 10))
    }

    func testDegenerateBoundsProduceAnUnusableLayout() {
        let layout = SliceCanvasLayout.make(pixelSize: pixelSize, bounds: .zero, zoom: 1, pan: .zero)
        XCTAssertFalse(layout.isUsable)
        XCTAssertEqual(layout.normalizedPoint(CGPoint(x: 10, y: 10)), .zero)
    }
}
