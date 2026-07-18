import SwiftUI
import XCTest
@testable import ImageKid

final class ToolShortcutTests: XCTestCase {
    func testPrimaryToolShortcutsDoNotUseBareTypingKeys() {
        let tools: [Tool] = [.view, .select, .pickColor, .crop, .resize, .refineBackground, .draw, .text]

        for tool in tools {
            XCTAssertTrue(
                tool.menuShortcutModifiers.contains(.command),
                "\(tool.label) should not use a bare key that can steal text input."
            )
            XCTAssertTrue(
                tool.menuShortcutModifiers.contains(.option),
                "\(tool.label) should use the tool-command modifier chord."
            )
        }
    }
}
