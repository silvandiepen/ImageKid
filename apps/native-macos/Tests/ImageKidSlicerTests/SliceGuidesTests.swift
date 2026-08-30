import CoreGraphics
import XCTest
@testable import ImageKidSlicer

final class SliceGuidesTests: XCTestCase {

    // MARK: - Auto layout

    func testOneVerticalCutMakesTwoSlicesLeftToRight() {
        let rects = SliceAutoLayout.rects(verticalCuts: [0.4], horizontalCuts: [])
        XCTAssertEqual(rects, [
            CGRect(x: 0, y: 0, width: 0.4, height: 1),
            CGRect(x: 0.4, y: 0, width: 0.6, height: 1)
        ])
    }

    func testCutsOnBothAxesMakeCellsInReadingOrder() {
        let rects = SliceAutoLayout.rects(verticalCuts: [0.5], horizontalCuts: [0.5])
        XCTAssertEqual(rects.count, 4)
        // Reading order: top-left, top-right, bottom-left, bottom-right.
        XCTAssertEqual(rects[0].origin, CGPoint(x: 0, y: 0))
        XCTAssertEqual(rects[1].origin, CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(rects[2].origin, CGPoint(x: 0, y: 0.5))
        XCTAssertEqual(rects[3].origin, CGPoint(x: 0.5, y: 0.5))
    }

    func testCutsAreSortedAndDeduplicated() {
        let rects = SliceAutoLayout.rects(verticalCuts: [0.75, 0.25, 0.25], horizontalCuts: [])
        XCTAssertEqual(rects.map(\.minX), [0, 0.25, 0.75])
    }

    func testCutsOnTheImageEdgeDoNotCreateEmptySlices() {
        let rects = SliceAutoLayout.rects(verticalCuts: [0, 1, 0.5], horizontalCuts: [])
        XCTAssertEqual(rects.count, 2)
    }

    func testSliverCellsAreDropped() {
        let rects = SliceAutoLayout.rects(verticalCuts: [0.5, 0.5001], horizontalCuts: [])
        XCTAssertEqual(rects.count, 2, "the hair between two near-identical guides is not a slice")
    }

    func testNoCutsMakeOneFullImageSlice() {
        XCTAssertEqual(
            SliceAutoLayout.rects(verticalCuts: [], horizontalCuts: []),
            [CGRect(x: 0, y: 0, width: 1, height: 1)]
        )
    }

    // MARK: - Grid

    func testGridOnlyReportsLinesWhenEnabled() {
        var grid = SliceGrid(isEnabled: false, columns: 4, rows: 2)
        XCTAssertTrue(grid.verticalLines.isEmpty)
        grid.isEnabled = true
        XCTAssertEqual(grid.verticalLines, [0.25, 0.5, 0.75])
        XCTAssertEqual(grid.horizontalLines, [0.5])
    }

    func testSingleColumnGridHasNoInteriorLines() {
        let grid = SliceGrid(isEnabled: true, columns: 1, rows: 1)
        XCTAssertTrue(grid.verticalLines.isEmpty)
        XCTAssertTrue(grid.horizontalLines.isEmpty)
    }

    // MARK: - Guides

    func testGuidePositionIsClampedToTheImage() {
        XCTAssertEqual(SliceGuide(axis: .vertical, position: -3).position, 0)
        XCTAssertEqual(SliceGuide(axis: .horizontal, position: 9).position, 1)
    }

    // MARK: - Templates

    func testTemplateFillsTheImageWithItsCells() {
        let template = SliceTemplate(name: "Quarters", columns: 2, rows: 2)
        let rects = template.rects
        XCTAssertEqual(rects.count, 4)
        XCTAssertEqual(template.sliceCount, 4)
        XCTAssertEqual(rects.reduce(CGFloat(0)) { $0 + $1.width * $1.height }, 1, accuracy: 0.0001)
    }

    func testTemplateDimensionsAreClampedToTheGridRange() {
        let template = SliceTemplate(name: "Silly", columns: 0, rows: 9999)
        XCTAssertEqual(template.columns, 1)
        XCTAssertEqual(template.rows, SliceGrid.range.upperBound)
    }

    func testBuiltInTemplatesAreAllUsable() {
        for template in SliceTemplate.builtIns {
            XCTAssertEqual(template.rects.count, template.sliceCount, "\(template.name) should produce every cell")
        }
    }
}
