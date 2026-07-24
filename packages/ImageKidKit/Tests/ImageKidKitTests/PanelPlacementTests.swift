import XCTest

@testable import ImageKidKit

final class PanelPlacementTests: XCTestCase {

    private let dock = CGSize(width: 1000, height: 700)

    // MARK: - Side derivation

    func testSideIsLeftWhenCentreLeftOfDockMidpoint() {
        XCTAssertEqual(
            PanelPlacement.side(ofPanelAt: 16, panelWidth: 240, dockWidth: 1000), .left)
    }

    func testSideIsRightWhenCentreRightOfDockMidpoint() {
        XCTAssertEqual(
            PanelPlacement.side(ofPanelAt: 744, panelWidth: 240, dockWidth: 1000), .right)
    }

    func testSideAtExactMidpointCountsAsRight() {
        // Centre exactly on the midpoint: 380 + 120 = 500.
        XCTAssertEqual(
            PanelPlacement.side(ofPanelAt: 380, panelWidth: 240, dockWidth: 1000), .right)
    }

    // MARK: - Edge-relative offsets

    func testEdgeOffsetRoundTripsOnBothSides() {
        for (x, side) in [(CGFloat(16), PanelDockSide.left), (744, .right)] {
            let offset = PanelPlacement.edgeOffset(
                forPanelAt: x, side: side, panelWidth: 240, dockWidth: 1000)
            let resolved = PanelPlacement.resolveX(
                side: side, edgeOffset: offset, panelWidth: 240, dockWidth: 1000)
            XCTAssertEqual(resolved, x, "side \(side)")
        }
    }

    func testRightAnchorHugsTheRightEdgeAcrossResizes() {
        // Trailing edge 16pt off the right edge of a 1000pt dock…
        let offset = PanelPlacement.edgeOffset(
            forPanelAt: 744, side: .right, panelWidth: 240, dockWidth: 1000)
        XCTAssertEqual(offset, 16)
        // …stays 16pt off the right edge when the window shrinks.
        XCTAssertEqual(
            PanelPlacement.resolveX(
                side: .right, edgeOffset: offset, panelWidth: 240, dockWidth: 800),
            544)
    }

    func testFlushRightAnchorStaysFlushAcrossResizes() {
        let offset = PanelPlacement.edgeOffset(
            forPanelAt: 760, side: .right, panelWidth: 240, dockWidth: 1000)
        XCTAssertEqual(offset, 0)
        XCTAssertEqual(
            PanelPlacement.resolveX(
                side: .right, edgeOffset: 0, panelWidth: 240, dockWidth: 1400),
            1160)
    }

    // MARK: - Clamping

    func testClampLeavesAnInsidePositionAlone() {
        XCTAssertEqual(
            PanelPlacement.clamped(
                CGPoint(x: 100, y: 100), panelSize: CGSize(width: 240, height: 300),
                dock: dock),
            CGPoint(x: 100, y: 100))
    }

    func testClampKeepsAtLeastMinVisibleWidthInside() {
        let size = CGSize(width: 240, height: 300)
        // Pushed off the right: only 80pt may hang back inside.
        XCTAssertEqual(
            PanelPlacement.clamped(CGPoint(x: 5000, y: 0), panelSize: size, dock: dock).x,
            920)
        // Pushed off the left: at least 80pt must remain inside.
        XCTAssertEqual(
            PanelPlacement.clamped(CGPoint(x: -5000, y: 0), panelSize: size, dock: dock).x,
            -160)
    }

    func testClampKeepsTheFullHeaderBarInsideVertically() {
        let size = CGSize(width: 240, height: 300)
        XCTAssertEqual(
            PanelPlacement.clamped(CGPoint(x: 0, y: -50), panelSize: size, dock: dock).y,
            0)
        XCTAssertEqual(
            PanelPlacement.clamped(CGPoint(x: 0, y: 5000), panelSize: size, dock: dock).y,
            700 - PanelPlacement.headerHeight)
    }

    func testClampPassesThroughOnDegenerateDock() {
        let position = CGPoint(x: 400, y: 9000)
        XCTAssertEqual(
            PanelPlacement.clamped(
                position, panelSize: CGSize(width: 240, height: 300), dock: .zero),
            position)
    }

    // MARK: - Edge sticking

    func testEdgeStickSnapsFlushWithinTolerance() {
        XCTAssertEqual(PanelPlacement.edgeStuckX(14, panelWidth: 240, dockWidth: 1000), 0)
        XCTAssertEqual(
            PanelPlacement.edgeStuckX(748, panelWidth: 240, dockWidth: 1000), 760)
    }

    func testEdgeStickLeavesTheMiddleAlone() {
        XCTAssertEqual(PanelPlacement.edgeStuckX(15, panelWidth: 240, dockWidth: 1000), 15)
        XCTAssertEqual(
            PanelPlacement.edgeStuckX(400, panelWidth: 240, dockWidth: 1000), 400)
        XCTAssertEqual(
            PanelPlacement.edgeStuckX(745, panelWidth: 240, dockWidth: 1000), 745)
    }

    // MARK: - Opening placement

    func testOverlapDetection() {
        let frame = CGRect(x: 0, y: 0, width: 240, height: 300)
        XCTAssertTrue(
            PanelPlacement.overlaps(frame, any: [CGRect(x: 200, y: 200, width: 50, height: 50)]))
        XCTAssertFalse(
            PanelPlacement.overlaps(frame, any: [CGRect(x: 400, y: 0, width: 50, height: 50)]))
        XCTAssertFalse(PanelPlacement.overlaps(frame, any: []))
    }

    func testOpeningSlotInAnEmptyDockStartsTopLeft() {
        XCTAssertEqual(
            PanelPlacement.openingSlot(
                panelSize: CGSize(width: 240, height: 300), dock: dock, openFrames: []),
            CGPoint(x: 8, y: 8))
    }

    func testOpeningSlotPrefersTheEmptierSide() {
        // One panel on the left — the right column has more room.
        let slot = PanelPlacement.openingSlot(
            panelSize: CGSize(width: 240, height: 300), dock: dock,
            openFrames: [CGRect(x: 8, y: 8, width: 240, height: 400)])
        XCTAssertEqual(slot, CGPoint(x: 1000 - 240 - 8, y: 8))
    }

    func testOpeningSlotStacksBelowTheLowestPanelOnItsSide() {
        // Left column ends at y 208, right at y 508 — left wins, below + gap.
        let slot = PanelPlacement.openingSlot(
            panelSize: CGSize(width: 240, height: 300), dock: dock,
            openFrames: [
                CGRect(x: 8, y: 8, width: 240, height: 200),
                CGRect(x: 752, y: 8, width: 240, height: 500),
            ])
        XCTAssertEqual(slot, CGPoint(x: 8, y: 220))
    }

    func testOpeningSlotIsClampedIntoTheDock() {
        // Both columns full to the bottom: the slot still keeps the header
        // bar inside the dock.
        let slot = PanelPlacement.openingSlot(
            panelSize: CGSize(width: 240, height: 300), dock: dock,
            openFrames: [
                CGRect(x: 16, y: 16, width: 240, height: 680),
                CGRect(x: 744, y: 16, width: 240, height: 680),
            ])
        XCTAssertEqual(slot.y, 700 - PanelPlacement.headerHeight)
    }
}
