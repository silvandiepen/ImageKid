import AppKit
import SwiftUI
import XCTest
@testable import ImageKidSlicer

/// The tooltip annotation. The point of these is geometry: two earlier
/// attempts set the right text on the wrong view, which no text-only
/// assertion could tell apart from working.
@MainActor
final class ToolTipTests: XCTestCase {

    /// Host a real control in a real window, and return every probe found.
    private func probes<Content: View>(in view: Content, size: CGSize) -> (root: NSView, probes: [ToolTipProbeView]) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        var found: [ToolTipProbeView] = []
        func walk(_ view: NSView) {
            if let probe = view as? ToolTipProbeView { found.append(probe) }
            view.subviews.forEach(walk)
        }
        walk(hosting)
        return (hosting, found)
    }

    func testTheTooltipRectIsRegisteredOnTheRootView() {
        let (_, found) = probes(
            in: Color.clear.frame(width: 40, height: 40).toolTip("Suggest Guides"),
            size: CGSize(width: 200, height: 100)
        )
        let probe = found.first
        XCTAssertNotNil(probe, "no annotation was hosted")
        XCTAssertNotNil(probe?.registeredRect, "nothing was registered — the tooltip cannot appear")
    }

    /// The failure that made two earlier attempts look fine and behave badly:
    /// the annotation was laid out outside its parent and clipped, so the
    /// rect it described was nowhere near the control.
    func testTheRectMatchesWhereTheControlActuallyIs() {
        let (root, found) = probes(
            in: HStack(spacing: 0) {
                Color.clear.frame(width: 40, height: 40).toolTip("first")
                Color.clear.frame(width: 40, height: 40).toolTip("second")
            }
            .frame(width: 200, height: 100),
            size: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(found.count, 2)
        for probe in found {
            let rect = try? XCTUnwrap(probe.registeredRect)
            guard let rect else { continue }
            XCTAssertTrue(
                root.bounds.contains(rect),
                "the tooltip rect \(rect) falls outside the root \(root.bounds) — it would be clipped")
            XCTAssertEqual(rect.width, 40, accuracy: 1)
            XCTAssertEqual(rect.height, 40, accuracy: 1)
        }

        let rects = found.compactMap(\.registeredRect)
        XCTAssertNotEqual(rects[0], rects[1], "neighbouring controls must describe different places")
    }

    func testEachProbeReportsItsOwnText() {
        let (_, found) = probes(
            in: HStack(spacing: 0) {
                Color.clear.frame(width: 40, height: 40).toolTip("first tool")
                Color.clear.frame(width: 40, height: 40).toolTip("second tool")
            },
            size: CGSize(width: 200, height: 100)
        )
        let texts = found.map { $0.view($0, stringForToolTip: 0, point: .zero, userData: nil) }
        XCTAssertEqual(Set(texts), ["first tool", "second tool"])
    }

    func testTheAnnotationNeverTakesAClick() {
        let probe = ToolTipProbeView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        XCTAssertNil(
            probe.hitTest(NSPoint(x: 20, y: 20)),
            "a hit-testable annotation would swallow the click meant for the control")
    }

    func testAnUnhostedAnnotationRegistersNothing() {
        let probe = ToolTipProbeView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        probe.tip = "nowhere"
        XCTAssertNil(probe.registeredRect, "with no window there is nothing to register on")
    }

    // MARK: - The real tool bar

    func testEveryToolBarIconRegistersARectInsideTheWindow() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "tooltips-\(UUID().uuidString)"))
        let model = SlicerDocumentModel(
            templates: SliceTemplateStore(store: suite),
            exports: ExportOptionsStore(store: suite)
        )
        let image = try TestImages.halves(width: 200, height: 100)
        model.adopt(SlicerDocumentModel.Source(
            url: nil, displayName: "sheet", image: image,
            preview: NSImage(cgImage: image, size: NSSize(width: 200, height: 100)),
            outputType: .png, fileExtension: "png"
        ))

        let (root, found) = probes(in: SlicerToolbar(model: model), size: CGSize(width: 760, height: 70))

        XCTAssertGreaterThanOrEqual(found.count, 10, "every icon in the bar should be described")
        for probe in found {
            let rect = probe.registeredRect
            XCTAssertNotNil(rect, "an icon registered nothing")
            if let rect {
                XCTAssertTrue(root.bounds.contains(rect), "\(rect) is clipped out of \(root.bounds)")
            }
        }
    }
}
