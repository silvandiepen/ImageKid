import Foundation
import XCTest
@testable import ImageKid

final class QuickActionTests: XCTestCase {
    func testParseQuickUpscaleAction() throws {
        let launch = try XCTUnwrap(
            QuickActionRunner.parse(arguments: ["ImageKid", "--quick-action", "upscale-2x", "/tmp/source.png"])
        )

        XCTAssertEqual(launch.definition.id, "upscale-2x")
        XCTAssertEqual(launch.definition.steps, [.upscale(scale: 2)])
        XCTAssertEqual(launch.sourceURLs.map(\.path), ["/tmp/source.png"])
    }

    func testParseBackgroundRemovalActionWithMultipleFiles() throws {
        let launch = try XCTUnwrap(
            QuickActionRunner.parse(
                arguments: ["ImageKid", "--quick-action", "remove-background", "/tmp/a.png", "/tmp/b.jpg"]
            )
        )

        XCTAssertEqual(launch.definition.id, "remove-background")
        XCTAssertEqual(launch.definition.steps, [.removeBackground])
        XCTAssertEqual(launch.sourceURLs.map(\.path), ["/tmp/a.png", "/tmp/b.jpg"])
    }

    func testParseCombinedDefaultAction() throws {
        let launch = try XCTUnwrap(
            QuickActionRunner.parse(arguments: ["ImageKid", "--quick-action", "marketplace-square", "/tmp/source.png"])
        )

        XCTAssertEqual(launch.definition.steps, [
            .removeBackground,
            .upscale(scale: 2),
            .canvas(width: 1024, height: 1024)
        ])
    }

    func testParseLegacyQuickUpscaleCommand() throws {
        let launch = try XCTUnwrap(
            QuickActionRunner.parse(arguments: ["ImageKid", "--quick-upscale", "4", "/tmp/source.png"])
        )

        XCTAssertEqual(launch.definition.id, "upscale-4x")
        XCTAssertEqual(launch.sourceURLs.map(\.path), ["/tmp/source.png"])
    }

    func testParseRejectsUnsupportedAction() {
        XCTAssertThrowsError(
            try QuickActionRunner.parse(arguments: ["ImageKid", "--quick-action", "resize", "/tmp/source.png"])
        )
    }

    func testUniqueOutputURLAddsSuffix() {
        let url = QuickActionRunner.uniqueOutputURL(
            for: URL(fileURLWithPath: "/tmp/source.png"),
            suffix: "background-removed",
            fileExtension: "png"
        )

        XCTAssertEqual(url.path, "/tmp/source-background-removed.png")
    }
}
