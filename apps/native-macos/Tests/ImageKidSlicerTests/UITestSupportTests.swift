import XCTest
@testable import ImageKidSlicer

final class UITestSupportTests: XCTestCase {

    func testARepeatedFlagYieldsEveryValue() {
        let arguments = [
            "/path/to/app",
            "--uitest-open", "/tmp/alpha.png",
            "--uitest-open", "/tmp/beta.png",
            "--uitest-save", "out"
        ]
        XCTAssertEqual(
            UITestMode.values(after: "--uitest-open", in: arguments),
            ["/tmp/alpha.png", "/tmp/beta.png"]
        )
        XCTAssertEqual(UITestMode.values(after: "--uitest-save", in: arguments), ["out"])
    }

    func testAMissingFlagYieldsNothing() {
        XCTAssertTrue(UITestMode.values(after: "--uitest-open", in: ["/path/to/app"]).isEmpty)
    }

    func testATrailingFlagWithNoValueIsIgnored() {
        XCTAssertTrue(UITestMode.values(after: "--uitest-open", in: ["/app", "--uitest-open"]).isEmpty)
    }
}
