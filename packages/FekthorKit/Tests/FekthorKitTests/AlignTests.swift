import XCTest

@testable import FekthorKit

final class AlignTests: XCTestCase {
    private func rect(_ id: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> GraphicNode
    {
        .shape(ShapeNode(id: id, kind: .rect(x: x, y: y, width: w, height: h, rx: nil, ry: nil)))
    }

    private func doc(_ nodes: [GraphicNode]) -> GraphicDocument {
        GraphicDocument(viewBox: ViewBox(width: 100, height: 100), nodes: nodes)
    }

    private func b(_ id: Int, _ d: GraphicDocument) -> Align.Bounds {
        Align.bounds(of: id, in: d)!
    }

    // MARK: - Align to selection bounds

    func testAlignLeftAndRight() {
        let d = doc([rect(0, 0, 0, 10, 10), rect(1, 20, 20, 10, 10), rect(2, 40, 40, 10, 10)])
        let ids: Set<Int> = [0, 1, 2]

        let left = Align.align(ids, edge: .left, in: d)
        for id in ids {
            XCTAssertEqual(b(id, left).minX, 0, accuracy: 1e-9)
        }
        // y untouched by a horizontal align.
        XCTAssertEqual(b(1, left).minY, 20, accuracy: 1e-9)

        let right = Align.align(ids, edge: .right, in: d)
        for id in ids {
            XCTAssertEqual(b(id, right).maxX, 50, accuracy: 1e-9)
        }
    }

    func testAlignCenters() {
        let d = doc([rect(0, 0, 0, 10, 10), rect(1, 30, 60, 20, 20)])
        let ids: Set<Int> = [0, 1]
        // Collective bounds: x 0..50, y 0..80.
        let cx = Align.align(ids, edge: .centerX, in: d)
        XCTAssertEqual((b(0, cx).minX + b(0, cx).maxX) / 2, 25, accuracy: 1e-9)
        XCTAssertEqual((b(1, cx).minX + b(1, cx).maxX) / 2, 25, accuracy: 1e-9)
        let cy = Align.align(ids, edge: .centerY, in: d)
        XCTAssertEqual((b(0, cy).minY + b(0, cy).maxY) / 2, 40, accuracy: 1e-9)
        XCTAssertEqual((b(1, cy).minY + b(1, cy).maxY) / 2, 40, accuracy: 1e-9)
    }

    func testAlignTopAndBottom() {
        let d = doc([rect(0, 0, 10, 10, 10), rect(1, 20, 30, 10, 40)])
        let ids: Set<Int> = [0, 1]
        let top = Align.align(ids, edge: .top, in: d)
        XCTAssertEqual(b(0, top).minY, 10, accuracy: 1e-9)
        XCTAssertEqual(b(1, top).minY, 10, accuracy: 1e-9)
        let bottom = Align.align(ids, edge: .bottom, in: d)
        XCTAssertEqual(b(0, bottom).maxY, 70, accuracy: 1e-9)
        XCTAssertEqual(b(1, bottom).maxY, 70, accuracy: 1e-9)
    }

    func testPrimitivesStayPrimitives() {
        let d = doc([rect(0, 0, 0, 10, 10), rect(1, 20, 20, 10, 10)])
        let out = Align.align([0, 1], edge: .left, in: d)
        guard case .shape(let moved) = out.nodes[1] else { return XCTFail() }
        guard case .rect(let x, let y, let w, let h, _, _) = moved.kind else {
            return XCTFail("rect must stay .rect after align")
        }
        XCTAssertEqual(x, 0, accuracy: 1e-9)
        XCTAssertEqual(y, 20, accuracy: 1e-9)
        XCTAssertEqual(w, 10, accuracy: 1e-9)
        XCTAssertEqual(h, 10, accuracy: 1e-9)
        XCTAssertNil(moved.transform)
    }

    func testCircleStaysCircle() {
        let circle = GraphicNode.shape(ShapeNode(id: 0, kind: .circle(center: Pt(30, 30), r: 5)))
        let d = doc([circle, rect(1, 0, 0, 10, 10)])
        let out = Align.align([0, 1], edge: .left, in: d)
        guard case .shape(let moved) = out.nodes[0],
            case .circle(let c, let r) = moved.kind
        else { return XCTFail("circle must stay .circle") }
        XCTAssertEqual(c.x, 5, accuracy: 1e-9)  // bounds minX 25 → 0, centre follows
        XCTAssertEqual(c.y, 30, accuracy: 1e-9)
        XCTAssertEqual(r, 5, accuracy: 1e-9)
    }

    func testTransformedNodeAlignsByBakedBounds() {
        // Rect at origin carrying translate(30 0): document bounds 30..40.
        let t = TransformValue(raw: "translate(30 0)", matrix: [1, 0, 0, 1, 30, 0])
        let transformed = GraphicNode.shape(
            ShapeNode(
                id: 0, kind: .rect(x: 0, y: 0, width: 10, height: 10, rx: nil, ry: nil),
                transform: t))
        let d = doc([transformed, rect(1, 0, 50, 10, 10)])
        let out = Align.align([0, 1], edge: .left, in: d)
        XCTAssertEqual(b(0, out).minX, 0, accuracy: 1e-9)
        guard case .shape(let moved) = out.nodes[0] else { return XCTFail() }
        // Translation composed onto the transform; primitive kind preserved.
        if case .rect = moved.kind {} else { XCTFail("kind must stay .rect") }
        XCTAssertEqual(moved.transform?.matrix ?? [], [1, 0, 0, 1, 0, 0])
    }

    func testAlignGroupMovesAsUnit() {
        let group = GraphicNode.group(
            GroupNode(id: 5, children: [rect(0, 20, 20, 10, 10), rect(1, 40, 20, 10, 10)]))
        let d = doc([group, rect(2, 0, 0, 10, 10)])
        // Group bounds 20..50; collective minX 0 → group shifts by -20.
        let out = Align.align([5, 2], edge: .left, in: d)
        XCTAssertEqual(b(5, out).minX, 0, accuracy: 1e-9)
        guard case .group(let g) = out.nodes[0] else { return XCTFail() }
        // Children untouched — the group gained a translation transform.
        XCTAssertEqual(g.transform?.matrix ?? [], [1, 0, 0, 1, -20, 0])
        guard case .shape(let child) = g.children[0], case .rect(let x, _, _, _, _, _) = child.kind
        else { return XCTFail() }
        XCTAssertEqual(x, 20, accuracy: 1e-9)
    }

    func testNestedSelectionUsesDocumentSpace() {
        // Rect inside a translated group; aligning the rect to the artboard
        // must account for the group's transform.
        let t = TransformValue(raw: "translate(10 10)", matrix: [1, 0, 0, 1, 10, 10])
        let group = GraphicNode.group(
            GroupNode(id: 5, transform: t, children: [rect(0, 20, 20, 10, 10)]))
        let d = doc([group])
        // Document-space bounds of the rect: 30..40.
        XCTAssertEqual(b(0, d).minX, 30, accuracy: 1e-9)
        let out = Align.alignToArtboard([0], edge: .left, in: d)
        XCTAssertEqual(b(0, out).minX, 0, accuracy: 1e-9)
    }

    // MARK: - Align to artboard

    func testAlignToArtboardCenter() {
        let d = doc([rect(0, 0, 0, 10, 20)])
        var out = Align.alignToArtboard([0], edge: .centerX, in: d)
        out = Align.alignToArtboard([0], edge: .centerY, in: out)
        let bounds = b(0, out)
        XCTAssertEqual((bounds.minX + bounds.maxX) / 2, 50, accuracy: 1e-9)
        XCTAssertEqual((bounds.minY + bounds.maxY) / 2, 50, accuracy: 1e-9)
    }

    func testAlignToArtboardRespectsViewBoxOrigin() {
        var d = doc([rect(0, 0, 0, 10, 10)])
        d.viewBox = ViewBox(minX: -50, minY: -50, width: 100, height: 100)
        let out = Align.alignToArtboard([0], edge: .left, in: d)
        XCTAssertEqual(b(0, out).minX, -50, accuracy: 1e-9)
    }

    // MARK: - Distribute

    func testDistributeHorizontalEqualGapsEndsFixed() {
        let d = doc([rect(0, 0, 0, 10, 10), rect(1, 15, 0, 10, 10), rect(2, 50, 0, 10, 10)])
        let out = Align.distribute([0, 1, 2], axis: .horizontal, in: d)
        // Span 0..60, sizes 30, gap (60-30)/2 = 15 → minX 0, 25, 50.
        XCTAssertEqual(b(0, out).minX, 0, accuracy: 1e-9)
        XCTAssertEqual(b(1, out).minX, 25, accuracy: 1e-9)
        XCTAssertEqual(b(2, out).minX, 50, accuracy: 1e-9)
        // Gaps equal.
        XCTAssertEqual(b(1, out).minX - b(0, out).maxX, b(2, out).minX - b(1, out).maxX,
            accuracy: 1e-9)
    }

    func testDistributeVerticalWithMixedSizes() {
        let d = doc([rect(0, 0, 0, 10, 10), rect(1, 0, 12, 10, 30), rect(2, 0, 80, 10, 20)])
        let out = Align.distribute([0, 1, 2], axis: .vertical, in: d)
        // Span 0..100, sizes 60, gap 20 → minY 0, 30, 80.
        XCTAssertEqual(b(0, out).minY, 0, accuracy: 1e-9)
        XCTAssertEqual(b(1, out).minY, 30, accuracy: 1e-9)
        XCTAssertEqual(b(2, out).minY, 80, accuracy: 1e-9)
        // Ends fixed.
        XCTAssertEqual(b(0, out).minY, 0, accuracy: 1e-9)
        XCTAssertEqual(b(2, out).maxY, 100, accuracy: 1e-9)
        // x untouched.
        XCTAssertEqual(b(1, out).minX, 0, accuracy: 1e-9)
    }

    func testDistributeNeedsAtLeastThree() {
        let d = doc([rect(0, 0, 0, 10, 10), rect(1, 90, 0, 10, 10)])
        XCTAssertEqual(Align.distribute([0, 1], axis: .horizontal, in: d), d)
    }

    // MARK: - Misc

    func testEmptyOrUnknownSelectionIsNoOp() {
        let d = doc([rect(0, 5, 5, 10, 10)])
        XCTAssertEqual(Align.align([], edge: .left, in: d), d)
        XCTAssertEqual(Align.align([99], edge: .left, in: d), d)
    }

    func testDeterministic() {
        let d = doc([rect(0, 0, 0, 10, 10), rect(1, 15, 20, 10, 10), rect(2, 50, 40, 10, 10)])
        XCTAssertEqual(
            Align.align([0, 1, 2], edge: .centerX, in: d),
            Align.align([0, 1, 2], edge: .centerX, in: d))
        XCTAssertEqual(
            Align.distribute([0, 1, 2], axis: .horizontal, in: d),
            Align.distribute([0, 1, 2], axis: .horizontal, in: d))
    }
}
