import XCTest

@testable import ImageKidKit

/// The rail's height-driven split: what stays on the rail, what moves behind
/// the overflow button. Fekthor's editor rail (14 palettes, 32pt chips, 6pt
/// gaps, 8pt inset, 69pt of paint wells on top) is the worked example.
final class PanelRailLayoutTests: XCTestCase {

    private let order = Array(1...14)

    private func split(_ height: CGFloat, count: Int = 14) -> (shown: [Int], hidden: [Int]) {
        PanelRailLayout.split(
            Array(1...count), height: height, chip: 32, spacing: 6, padding: 8, reserved: 69)
    }

    func testEverythingFitsInATallWindow() {
        // 14 chips need 14·38 − 6 = 526, plus 69 wells and 16 inset = 611.
        let result = split(700)
        XCTAssertEqual(result.shown, order)
        XCTAssertTrue(result.hidden.isEmpty, "no overflow button when everything fits")
    }

    func testExactFitDoesNotOpenAnOverflow() {
        XCTAssertTrue(split(611).hidden.isEmpty)
    }

    /// One chip short of fitting: the overflow button takes a slot too, so
    /// TWO buttons move behind it — the head of the order stays put.
    func testOneChipTooManyMovesTwoIntoTheOverflow() {
        let result = split(611 - 38)
        XCTAssertEqual(result.shown, Array(1...12))
        XCTAssertEqual(result.hidden, [13, 14])
    }

    /// 300pt of rail leaves 215 for chips — five slots, one of which the
    /// overflow button takes.
    func testShortWindowKeepsTheHeadOfTheOrder() {
        let result = split(300)
        XCTAssertEqual(result.shown, [1, 2, 3, 4])
        XCTAssertEqual(result.hidden, Array(5...14))
        XCTAssertEqual(result.shown.count + result.hidden.count, order.count)
    }

    /// However cramped, the rail never renders empty — one chip plus the
    /// overflow beats zero buttons.
    func testDegenerateHeightStillShowsOneChip() {
        for height in [CGFloat(0), 40, -100] {
            let result = split(height)
            XCTAssertEqual(result.shown.count, 1, "height \(height)")
            XCTAssertEqual(result.hidden.count, 13, "height \(height)")
        }
    }

    func testEmptyOrderSplitsIntoNothing() {
        let result = PanelRailLayout.split(
            [Int](), height: 700, chip: 32, spacing: 6, padding: 8, reserved: 69)
        XCTAssertTrue(result.shown.isEmpty)
        XCTAssertTrue(result.hidden.isEmpty)
    }

    func testSingleButtonNeverNeedsAnOverflow() {
        let result = split(100, count: 1)
        XCTAssertEqual(result.shown, [1])
        XCTAssertTrue(result.hidden.isEmpty)
    }
}
