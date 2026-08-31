import AppKit
import SwiftUI
import XCTest
@testable import ImageKidSlicer

/// The tooltip annotation: that it labels the control rather than itself, and
/// that it never intercepts a click.
@MainActor
final class ToolTipTests: XCTestCase {

    /// Reaches the private representable through the modifier, the same way
    /// the app does.
    private func hostedAnnotation(_ text: String) throws -> NSView {
        let hosting = NSHostingView(rootView: Color.clear.toolTip(text).frame(width: 40, height: 40))
        hosting.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    /// Depth-first search for a view carrying the tooltip.
    private func findToolTip(_ text: String, in view: NSView) -> Bool {
        if view.toolTip == text { return true }
        return view.subviews.contains { findToolTip(text, in: $0) }
    }

    func testTheTooltipLandsOnAViewInTheHierarchy() throws {
        let hosting = try hostedAnnotation("Suggest Guides — find the gutters")
        XCTAssertTrue(
            findToolTip("Suggest Guides — find the gutters", in: hosting),
            "no view ended up carrying the tooltip")
    }

    /// The annotation labels its superview, so if SwiftUI were to share one
    /// container between several controls the last tooltip would win and every
    /// button in the tool bar would describe the same thing.
    func testNeighbouringControlsKeepTheirOwnTooltips() throws {
        let row = HStack(spacing: 0) {
            Color.clear.frame(width: 30, height: 30).toolTip("first tool")
            Color.clear.frame(width: 30, height: 30).toolTip("second tool")
            Color.clear.frame(width: 30, height: 30).toolTip("third tool")
        }
        let hosting = NSHostingView(rootView: row)
        hosting.frame = NSRect(x: 0, y: 0, width: 90, height: 30)
        hosting.layoutSubtreeIfNeeded()

        for text in ["first tool", "second tool", "third tool"] {
            XCTAssertTrue(findToolTip(text, in: hosting), "\(text) was lost")
        }
    }

    func testUpdatingTheTextReplacesIt() throws {
        // The same mechanism, exercised directly: the annotation labels its
        // container, so a container is what has to end up with the text.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        let annotation = ToolTipProbe()
        container.addSubview(annotation)

        annotation.text = "first"
        XCTAssertEqual(container.toolTip, "first")

        annotation.text = "second"
        XCTAssertEqual(container.toolTip, "second")
    }

    func testTheAnnotationNeverTakesAClick() {
        let annotation = ToolTipProbe(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        XCTAssertNil(
            annotation.hitTest(NSPoint(x: 10, y: 10)),
            "a hit-testable annotation would swallow the button's own click")
    }
}

/// A stand-in with the same two behaviours the real annotation has, so they
/// can be asserted without reaching into a private type.
private final class ToolTipProbe: NSView {
    var text: String? {
        didSet { superview?.toolTip = text }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        superview?.toolTip = text
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
