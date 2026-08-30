import AppKit
import XCTest
@testable import ImageKidSlicer

final class SlicerToolbarSymbolTests: XCTestCase {

    /// A symbol name that does not exist on the deployment target draws an
    /// empty button and reports nothing, so the toolbar's names are checked
    /// here rather than discovered in a screenshot.
    func testEveryToolbarSymbolResolves() {
        for name in SlicerToolbar.Symbol.all {
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "SF Symbol \"\(name)\" does not exist on this deployment target"
            )
        }
    }

    func testEveryToolHasItsOwnSymbolAndLabel() {
        let symbols = Set(SlicerTool.allCases.map(\.symbolName))
        let labels = Set(SlicerTool.allCases.map(\.label))
        XCTAssertEqual(symbols.count, SlicerTool.allCases.count)
        XCTAssertEqual(labels.count, SlicerTool.allCases.count)
    }
}
