import CoreGraphics
import XCTest
@testable import ImageKidSlicer

/// Finding each separate thing in an image, wherever it sits.
final class SliceElementDetectionTests: XCTestCase {

    private func canvas(_ width: Int, _ height: Int, _ boxes: [CGRect]) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.9, alpha: 1))
        for box in boxes { context.fill(box) }
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    // MARK: - Components

    func testTouchingPixelsFormOneBoxAndSeparateOnesDoNot() {
        // 5×3. Two blobs with a background column between them.
        let content = [
            true,  true,  false, true,  false,
            true,  true,  false, true,  false,
            false, false, false, false, false
        ]
        let boxes = SliceDetection.boundingBoxes(ofComponentsIn: content, width: 5, height: 3)
        XCTAssertEqual(boxes.count, 2)
        XCTAssertEqual(boxes[0], CGRect(x: 0, y: 0, width: 2, height: 2))
        XCTAssertEqual(boxes[1], CGRect(x: 3, y: 0, width: 1, height: 2))
    }

    func testDiagonallyTouchingPixelsAreTheSameThing() {
        let content = [
            true,  false,
            false, true
        ]
        XCTAssertEqual(SliceDetection.boundingBoxes(ofComponentsIn: content, width: 2, height: 2).count, 1)
    }

    func testAnEmptyMaskHasNoComponents() {
        XCTAssertTrue(SliceDetection.boundingBoxes(
            ofComponentsIn: [Bool](repeating: false, count: 9), width: 3, height: 3).isEmpty)
    }

    // MARK: - Merging and ordering

    func testNearNeighboursMergeIntoOneThing() {
        let boxes = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 12, y: 0, width: 10, height: 10)   // 2px apart
        ]
        XCTAssertEqual(SliceDetection.merged(boxes, within: 3).count, 1)
        XCTAssertEqual(SliceDetection.merged(boxes, within: 0).count, 2)
    }

    func testMergingIsTransitiveAcrossAChain() {
        let boxes = [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 12, y: 0, width: 10, height: 10),
            CGRect(x: 24, y: 0, width: 10, height: 10)
        ]
        let merged = SliceDetection.merged(boxes, within: 3)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0], CGRect(x: 0, y: 0, width: 34, height: 10))
    }

    func testReadingOrderIsLeftToRightThenTopToBottom() {
        let boxes = [
            CGRect(x: 100, y: 0, width: 20, height: 20),   // top right
            CGRect(x: 0, y: 100, width: 20, height: 20),   // bottom left
            CGRect(x: 0, y: 5, width: 20, height: 20)      // top left, ragged
        ]
        XCTAssertEqual(
            SliceDetection.readingOrder(boxes).map(\.origin),
            [CGPoint(x: 0, y: 5), CGPoint(x: 100, y: 0), CGPoint(x: 0, y: 100)]
        )
    }

    // MARK: - Whole images

    func testAScatteredCollageBecomesOneSlicePerElement() throws {
        // The case projection cannot do: three boxes that share no full-width
        // gutter. CGContext draws bottom-up, so these are listed accordingly.
        let image = try canvas(300, 200, [
            CGRect(x: 20, y: 120, width: 80, height: 60),
            CGRect(x: 150, y: 90, width: 100, height: 80),
            CGRect(x: 60, y: 20, width: 70, height: 50)
        ])

        let elements = SliceDetection.elements(in: image)
        XCTAssertEqual(elements.count, 3, "three things, three slices")

        // Compare with what gutters give: a grid that matches nothing.
        let gutters = SliceDetection.gutters(in: image)
        XCTAssertEqual(
            SliceAutoLayout.rects(verticalCuts: gutters.vertical, horizontalCuts: gutters.horizontal).count,
            4,
            "projection can only ever produce a grid")
    }

    func testEachBoxIsTheElementsOwnBounds() throws {
        let image = try canvas(200, 100, [CGRect(x: 40, y: 20, width: 60, height: 50)])
        let element = try XCTUnwrap(SliceDetection.elements(in: image).first)

        XCTAssertEqual(element.minX * 200, 40, accuracy: 2)
        XCTAssertEqual(element.width * 200, 60, accuracy: 2)
        // Drawn at y=20 bottom-up in a 100-tall canvas → 30 from the top.
        XCTAssertEqual(element.minY * 100, 30, accuracy: 2)
        XCTAssertEqual(element.height * 100, 50, accuracy: 2)
    }

    func testSpecksAreNotElements() throws {
        let image = try canvas(400, 400, [
            CGRect(x: 40, y: 40, width: 120, height: 120),
            CGRect(x: 300, y: 300, width: 2, height: 2)     // dust
        ])
        XCTAssertEqual(SliceDetection.elements(in: image).count, 1)
    }

    func testAGridSheetAlsoWorksElementByElement() throws {
        var tiles: [CGRect] = []
        for row in 0..<2 {
            for column in 0..<3 {
                tiles.append(CGRect(x: 10 + column * 70, y: 10 + row * 70, width: 60, height: 60))
            }
        }
        let image = try canvas(220, 150, tiles)
        XCTAssertEqual(SliceDetection.elements(in: image).count, 6)
    }

    func testAnImageWithNoBackgroundGapsFindsNothingUseful() throws {
        let image = try TestImages.halves(width: 120, height: 80)
        // Two abutting blocks and no background at all: the border pixels are
        // themselves content, so there is nothing to separate.
        XCTAssertLessThanOrEqual(SliceDetection.elements(in: image).count, 1)
    }
}
