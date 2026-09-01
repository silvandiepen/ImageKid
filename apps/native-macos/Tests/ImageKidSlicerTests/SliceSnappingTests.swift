import CoreGraphics
import XCTest
@testable import ImageKidSlicer

final class SliceSnappingTests: XCTestCase {
    private let threshold: CGFloat = 0.02

    private func targets(
        slices: [Slice] = [],
        excluding: Slice.ID? = nil,
        guides: [SliceGuide] = [],
        grid: SliceGrid = SliceGrid(),
        centres: Bool = true
    ) -> SnapTargets {
        SliceSnapping.targets(
            slices: slices,
            excluding: excluding,
            guides: guides,
            grid: grid,
            includeCentreLines: centres
        )
    }

    // MARK: - Targets

    func testImageEdgesAndCentreAreAlwaysTargets() {
        let result = targets()
        XCTAssertEqual(result.vertical.sorted(), [0, 0.5, 1])
        XCTAssertEqual(result.horizontal.sorted(), [0, 0.5, 1])
    }

    func testCentreLinesCanBeSwitchedOff() {
        let result = targets(centres: false)
        XCTAssertFalse(result.vertical.contains(0.5))
    }

    func testOtherSlicesGuidesAndGridAllContributeTargets() {
        let other = Slice(rect: CGRect(x: 0.2, y: 0.1, width: 0.2, height: 0.2))
        let result = targets(
            slices: [other],
            guides: [SliceGuide(axis: .vertical, position: 0.8)],
            grid: SliceGrid(isEnabled: true, columns: 4, rows: 1)
        )
        XCTAssertTrue(result.vertical.contains(0.2), "another slice's leading edge")
        XCTAssertTrue(result.vertical.contains(0.4), "another slice's trailing edge")
        XCTAssertTrue(result.vertical.contains(0.8), "a guide")
        XCTAssertTrue(result.vertical.contains(0.25), "a grid line")
    }

    func testTheDraggedSliceIsNeverItsOwnSnapTarget() {
        let dragged = Slice(rect: CGRect(x: 0.31, y: 0.1, width: 0.2, height: 0.2))
        let result = targets(slices: [dragged], excluding: dragged.id)
        XCTAssertFalse(result.vertical.contains(0.31))
    }

    // MARK: - Moving

    func testMovingSnapsTheWholeRectangleWithoutResizingIt() {
        let neighbour = Slice(rect: CGRect(x: 0.6, y: 0, width: 0.2, height: 1))
        // Deliberately closer to the neighbour's edge than to the centre
        // line, so the nearest-target rule is what is under test.
        let dragged = CGRect(x: 0.42, y: 0.3, width: 0.175, height: 0.2)

        let result = SliceSnapping.snapMoved(
            dragged,
            targets: targets(slices: [neighbour]),
            thresholdX: threshold,
            thresholdY: threshold
        )

        XCTAssertEqual(result.rect.maxX, 0.6, accuracy: 0.0001, "the trailing edge should meet the neighbour")
        XCTAssertEqual(result.rect.width, dragged.width, accuracy: 0.0001, "a move must never resize")
        XCTAssertEqual(result.verticalLines, [0.6])
    }

    func testMovingReportsNoLineWhenNothingIsClose() {
        let result = SliceSnapping.snapMoved(
            CGRect(x: 0.2, y: 0.2, width: 0.11, height: 0.11),
            targets: targets(centres: false),
            thresholdX: 0.005,
            thresholdY: 0.005
        )
        XCTAssertTrue(result.verticalLines.isEmpty)
        XCTAssertTrue(result.horizontalLines.isEmpty)
    }

    func testMovingSnapsOnTheCentreLine() {
        let result = SliceSnapping.snapMoved(
            CGRect(x: 0.398, y: 0.2, width: 0.2, height: 0.2),
            targets: targets(),
            thresholdX: threshold,
            thresholdY: threshold
        )
        XCTAssertEqual(result.rect.midX, 0.5, accuracy: 0.0001)
    }

    // MARK: - Resizing

    func testResizingOnlySnapsTheMovingEdges() {
        let guide = SliceGuide(axis: .vertical, position: 0.75)
        let result = SliceSnapping.snapEdges(
            CGRect(x: 0.205, y: 0.2, width: 0.54, height: 0.4),
            movingLeft: false, movingRight: true, movingTop: false, movingBottom: false,
            targets: targets(guides: [guide]),
            thresholdX: threshold,
            thresholdY: threshold
        )
        XCTAssertEqual(result.rect.maxX, 0.75, accuracy: 0.0001, "the dragged edge snaps to the guide")
        XCTAssertEqual(result.rect.minX, 0.205, accuracy: 0.0001, "the anchored edge must not move")
    }

    func testDrawingSnapsEveryEdge() {
        let result = SliceSnapping.snapEdges(
            CGRect(x: 0.004, y: 0.004, width: 0.492, height: 0.492),
            movingLeft: true, movingRight: true, movingTop: true, movingBottom: true,
            targets: targets(),
            thresholdX: threshold,
            thresholdY: threshold
        )
        XCTAssertEqual(result.rect, CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
    }

    // MARK: - Guides

    func testGuidesSnapToOtherLines() {
        let snapped = SliceSnapping.snapGuide(
            0.507,
            axis: .vertical,
            targets: targets(),
            threshold: threshold
        )
        XCTAssertEqual(snapped, 0.5, accuracy: 0.0001)
    }

    func testGuideKeepsItsPositionWhenNothingIsInRange() {
        let snapped = SliceSnapping.snapGuide(
            0.31,
            axis: .horizontal,
            targets: targets(centres: false),
            threshold: threshold
        )
        XCTAssertEqual(snapped, 0.31, accuracy: 0.0001)
    }

    func testNearestTargetWinsOverAFartherOne() {
        XCTAssertEqual(SliceSnapping.snap(0.52, to: [0.5, 0.53, 0.9], threshold: 0.05), 0.53)
        XCTAssertNil(SliceSnapping.snap(0.52, to: [0.1, 0.9], threshold: 0.05))
    }
}
