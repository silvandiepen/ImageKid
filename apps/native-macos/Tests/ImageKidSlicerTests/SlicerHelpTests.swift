import AppKit
import XCTest
@testable import ImageKidSlicer

/// Menu tooltips: that every command has one, and that adding a command
/// without one fails here rather than being noticed by hovering.
@MainActor
final class SlicerHelpTests: XCTestCase {

    /// Titles that are built from data at runtime, so they cannot be listed.
    private let dynamicTitles: Set<String> = ["\\(template.name) — \\(template.columns) × \\(template.rows)"]

    private func commandTitles() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ImageKidSlicerTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // native-macos
            .appendingPathComponent("Sources/ImageKidSlicer/SlicerCommands.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        // Every literal Button/Toggle/Menu title in the commands.
        let pattern = #"(?:Button|Toggle|Menu)\("([^"]+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
    }

    func testEveryMenuCommandHasATooltip() throws {
        let missing = try commandTitles()
            .filter { !$0.contains("\\(") && !dynamicTitles.contains($0) }
            .filter { SlicerHelp.byMenuTitle[$0] == nil }

        XCTAssertTrue(
            missing.isEmpty,
            "no tooltip for: \(missing.sorted().joined(separator: ", ")) — add them to SlicerHelp.byMenuTitle")
    }

    func testTitlesThatFlipWithStateAreCoveredBothWays() {
        for pair in [("Lock Slice", "Unlock Slice"), ("Show Slices List", "Hide Slices List")] {
            XCTAssertNotNil(SlicerHelp.byMenuTitle[pair.0], pair.0)
            XCTAssertNotNil(SlicerHelp.byMenuTitle[pair.1], pair.1)
        }
    }

    func testTooltipsAreSentencesNotRestatementsOfTheTitle() {
        for (title, help) in SlicerHelp.byMenuTitle {
            XCTAssertGreaterThan(help.count, title.count, "\(title): the tooltip should say more than the title")
            XCTAssertTrue(help.hasSuffix("."), "\(title): should read as a sentence")
        }
    }

    // MARK: - Applying them

    func testApplyingWalksSubmenusAndSetsTooltips() {
        let menu = NSMenu()
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Open Image…", action: nil, keyEquivalent: ""))
        file.submenu = fileMenu
        menu.addItem(file)

        SlicerHelp.applyTooltips(to: menu)

        XCTAssertEqual(fileMenu.items[0].toolTip, SlicerHelp.byMenuTitle["Open Image…"])
    }

    func testTemplateItemsGetTheSharedTooltipFromTheirSubmenu() {
        let menu = NSMenu()
        let templates = NSMenuItem(title: "Templates", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Templates")
        submenu.addItem(NSMenuItem(title: "Quarters — 2 × 2", action: nil, keyEquivalent: ""))
        templates.submenu = submenu
        menu.addItem(templates)

        SlicerHelp.applyTooltips(to: menu)

        XCTAssertEqual(templates.toolTip, SlicerHelp.byMenuTitle["Templates"])
        XCTAssertEqual(submenu.items[0].toolTip, SlicerHelp.templateItem)
    }

    func testAnUnknownItemIsLeftAloneRatherThanGivenTheWrongText() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Something Else", action: nil, keyEquivalent: ""))
        SlicerHelp.applyTooltips(to: menu)
        XCTAssertNil(menu.items[0].toolTip)
    }
}
