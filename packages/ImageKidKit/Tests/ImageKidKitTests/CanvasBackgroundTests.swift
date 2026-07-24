import XCTest

@testable import ImageKidKit

final class CanvasBackgroundTests: XCTestCase {
    func testHexRoundTrip() {
        let rgb = CanvasBackground.rgb(fromHex: "#7ABBDC")
        XCTAssertEqual(rgb?.r ?? 0, 0x7A / 255, accuracy: 1e-9)
        XCTAssertEqual(rgb?.g ?? 0, 0xBB / 255, accuracy: 1e-9)
        XCTAssertEqual(rgb?.b ?? 0, 0xDC / 255, accuracy: 1e-9)
        // A missing hash still parses; garbage does not.
        XCTAssertNotNil(CanvasBackground.rgb(fromHex: "010101"))
        XCTAssertNil(CanvasBackground.rgb(fromHex: "#12"))
        XCTAssertNil(CanvasBackground.rgb(fromHex: "not-a-colour"))
    }

    func testCheckerboardHasNoBaseColour() {
        XCTAssertNil(CanvasBackground(style: .checkerboard).baseColor)
        XCTAssertNotNil(CanvasBackground(style: .light).baseColor)
        XCTAssertNotNil(CanvasBackground(style: .dark).baseColor)
        XCTAssertNotNil(CanvasBackground(style: .custom, customHex: "#112233").baseColor)
    }

    func testOpacityIsClamped() {
        XCTAssertEqual(CanvasBackground(style: .dark, opacity: 5).opacity, 1)
        XCTAssertEqual(CanvasBackground(style: .dark, opacity: -3).opacity, 0)
    }

    func testReadsAsDark() {
        XCTAssertFalse(CanvasBackground(style: .checkerboard).readsAsDark)
        XCTAssertFalse(CanvasBackground(style: .light).readsAsDark)
        // A near-opaque dark surround reads dark; a fully transparent one
        // defers to the (dark) surface behind and does not.
        XCTAssertTrue(CanvasBackground(style: .dark, opacity: 1).readsAsDark)
        XCTAssertFalse(CanvasBackground(style: .dark, opacity: 0).readsAsDark)
        // A solid white custom colour reads light; solid black reads dark.
        XCTAssertFalse(CanvasBackground(style: .custom, customHex: "#ffffff", opacity: 1).readsAsDark)
        XCTAssertTrue(CanvasBackground(style: .custom, customHex: "#000000", opacity: 1).readsAsDark)
    }

    func testAppDefaultsMatchHistoricalLooks() {
        XCTAssertEqual(CanvasBackground.imageKidDefault.style, .checkerboard)
        XCTAssertEqual(CanvasBackground.imageKidDefault.opacity, 1)
        // Fekthor's "pure glass": a wash at zero opacity.
        XCTAssertEqual(CanvasBackground.fekthorDefault.opacity, 0)
    }

    func testEveryStyleLabelIsDistinct() {
        let labels = CanvasBackground.Style.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count)
    }
}
