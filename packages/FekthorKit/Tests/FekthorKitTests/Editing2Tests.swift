import XCTest

@testable import FekthorKit

final class Editing2Tests: XCTestCase {
    func testPrimitiveExpandsOnAnchorEdit() {
        let node = ShapeNode(id: 0, kind: .rect(x: 0, y: 0, width: 10, height: 10, rx: nil, ry: nil))
        let anchors = Editing2.anchors(of: node)
        XCTAssertEqual(anchors.count, 4)  // closed seam deduped
        let moved = Editing2.moveAnchor(node, path: 0, anchor: 1, to: Pt(12, -2))
        guard case .path(let paths) = moved.kind else { return XCTFail("should expand") }
        XCTAssertEqual(paths[0].segments[0].endPoint, Pt(12, -2))
        XCTAssertNil(moved.transform)
        // Untouched node keeps its primitive.
        if case .rect = node.kind {} else { XCTFail() }
    }

    func testCirclePathifyStaysOnCircle() {
        let node = ShapeNode(id: 0, kind: .circle(center: Pt(36, 36), r: 10))
        let paths = Editing2.bakedPaths(of: node)
        for p in PathRefine.flatten(paths[0]) {
            let r = ((p.x - 36) * (p.x - 36) + (p.y - 36) * (p.y - 36)).squareRoot()
            XCTAssertEqual(r, 10, accuracy: 0.05)
        }
    }

    func testTransformBakesOnEdit() {
        let node = ShapeNode(
            id: 0, kind: .line(Pt(0, 0), Pt(10, 0)),
            transform: TransformValue(raw: "translate(5 5)", matrix: [1, 0, 0, 1, 5, 5]))
        let anchors = Editing2.anchors(of: node)
        XCTAssertEqual(anchors[0].position, Pt(5, 5))  // anchors reported baked
        let moved = Editing2.moveAnchor(node, path: 0, anchor: 0, to: Pt(5, 6))
        XCTAssertNil(moved.transform)
        guard case .path(let paths) = moved.kind else { return XCTFail() }
        XCTAssertEqual(paths[0].start, Pt(5, 6))
        XCTAssertEqual(paths[0].segments[0].endPoint, Pt(15, 5))  // other end baked
    }

    func testHandleMirrorViaWrapper() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let node = ShapeNode(id: 0, kind: .path([rp]))
        let hs = Editing2.handles(of: node, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        let moved = Editing2.moveHandle(
            node, path: 0, segment: 1, kind: .c1, to: Pt(13, 6), mirror: true)
        guard case .path(let paths) = moved.kind,
            case .cubic(_, let c2a, _) = paths[0].segments[0],
            case .cubic(let c1b, _, _) = paths[0].segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1b.y, 6, accuracy: 1e-9)
        // Mirror: opposite handle collinear through the anchor (10,0) with
        // its OWN length (3) preserved.
        let v = (x: c2a.x - 10, y: c2a.y - 0)
        let len = (v.x * v.x + v.y * v.y).squareRoot()
        XCTAssertEqual(len, 3, accuracy: 1e-9)
        // Direction opposite to (dragged - anchor) = (3, 6).
        XCTAssertEqual(v.x * 6 - v.y * 3, 0, accuracy: 1e-9)  // collinear
        XCTAssertLessThan(v.x, 0)
        XCTAssertLessThan(v.y, 0)
    }

    func testRemoveAnchorAndMinimumGuard() {
        let node = ShapeNode(id: 0, kind: .polyline([Pt(0, 0), Pt(10, 0), Pt(20, 0)]))
        let removed = Editing2.removeAnchor(node, path: 0, anchor: 1)
        XCTAssertNotNil(removed)
        guard case .path(let paths)? = removed?.kind else { return XCTFail() }
        XCTAssertEqual(paths[0].segments.count, 1)
        let tiny = ShapeNode(id: 0, kind: .line(Pt(0, 0), Pt(5, 5)))
        XCTAssertNil(Editing2.removeAnchor(tiny, path: 0, anchor: 1))
    }

    func testInsertAnchorSplitsSegmentAndPreservesGeometry() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [.cubic(c1: Pt(3, 8), c2: Pt(7, -6), to: Pt(10, 0))], closed: false)
        let node = ShapeNode(id: 0, kind: .path([rp]))
        let before = Editing2.anchors(of: node).count
        let split = Editing2.insertAnchor(node, path: 0, segment: 0, t: 0.4)
        XCTAssertEqual(Editing2.anchors(of: split).count, before + 1)
        guard case .path(let paths) = split.kind else { return XCTFail() }
        // Every point of the split path stays on the original curve.
        for p in PathRefine.flatten(paths[0]) {
            XCTAssertLessThan(Editing.closestPoint(on: rp, to: p).distance, 0.05)
        }
    }

    func testInsertAnchorDegradesPrimitiveAndClampsT() {
        let node = ShapeNode(id: 0, kind: .rect(x: 0, y: 0, width: 10, height: 10, rx: nil, ry: nil))
        let before = Editing2.anchors(of: node).count
        let split = Editing2.insertAnchor(node, path: 0, segment: 0, t: 0.5)
        guard case .path = split.kind else { return XCTFail("primitive should degrade") }
        XCTAssertEqual(Editing2.anchors(of: split).count, before + 1)
        // t out of range clamps; the split still adds exactly one anchor.
        let clamped = Editing2.insertAnchor(node, path: 0, segment: 0, t: 1.7)
        XCTAssertEqual(Editing2.anchors(of: clamped).count, before + 1)
    }

    func testInsertAnchorOnClosedCircleKeepsShape() {
        let node = ShapeNode(id: 0, kind: .circle(center: Pt(0, 0), r: 10))
        let split = Editing2.insertAnchor(node, path: 0, segment: 1, t: 0.5)
        guard case .path(let paths) = split.kind else { return XCTFail() }
        XCTAssertTrue(paths[0].closed)
        XCTAssertEqual(paths[0].segments.count, 5)  // 4 quarter cubics + 1
        for p in PathRefine.flatten(paths[0]) {
            XCTAssertEqual((p.x * p.x + p.y * p.y).squareRoot(), 10, accuracy: 0.06)
        }
    }

    func testClosestPointMatchesInsertIndices() {
        let node = ShapeNode(id: 0, kind: .polyline([Pt(0, 0), Pt(10, 0), Pt(10, 10)]))
        guard let hit = Editing2.closestPoint(of: node, to: Pt(6, 1)) else { return XCTFail() }
        XCTAssertEqual(hit.path, 0)
        XCTAssertEqual(hit.segment, 0)
        XCTAssertEqual(hit.t, 0.6, accuracy: 1e-6)
        XCTAssertEqual(hit.distance, 1, accuracy: 1e-6)
        let split = Editing2.insertAnchor(node, path: hit.path, segment: hit.segment, t: hit.t)
        let anchors = Editing2.anchors(of: split)
        // New anchor index is segment + 1 and sits at the hit point.
        XCTAssertEqual(anchors[hit.segment + 1].position.x, 6, accuracy: 1e-6)
        XCTAssertEqual(anchors[hit.segment + 1].position.y, 0, accuracy: 1e-6)
    }

    func testTranslatePreservesPrimitivesAndTransforms() {
        let rect = ShapeNode(id: 0, kind: .rect(x: 1, y: 2, width: 3, height: 4, rx: 1, ry: nil))
        let moved = Editing2.translated(rect, dx: 10, dy: 20)
        guard case .rect(let x, let y, _, _, let rx, _) = moved.kind else { return XCTFail() }
        XCTAssertEqual(x, 11)
        XCTAssertEqual(y, 22)
        XCTAssertEqual(rx, 1)

        let t = ShapeNode(
            id: 0, kind: .circle(center: Pt(0, 0), r: 5),
            transform: TransformValue(raw: "rotate(45)", matrix: [0.7, 0.7, -0.7, 0.7, 0, 0]))
        let movedT = Editing2.translated(t, dx: 3, dy: 4)
        XCTAssertEqual(movedT.transform!.matrix[4], 3)
        XCTAssertEqual(movedT.transform!.matrix[5], 4)
        if case .circle(let c, _) = movedT.kind {
            XCTAssertEqual(c, Pt(0, 0))  // geometry untouched; offset in transform
        } else {
            XCTFail()
        }
    }

    // MARK: - Z-order & group/ungroup (Model2Ops)

    private func shape(_ id: Int) -> GraphicNode {
        .shape(ShapeNode(id: id, kind: .rect(x: 0, y: 0, width: 5, height: 5, rx: nil, ry: nil)))
    }

    private func ids(_ nodes: [GraphicNode]) -> [Int] { nodes.map { $0.id } }

    func testZOrderOps() {
        var doc = GraphicDocument(viewBox: ViewBox(width: 100, height: 100))
        doc.nodes = [shape(0), shape(1), shape(2), shape(3)]
        doc.bringForward([1])
        XCTAssertEqual(ids(doc.nodes), [0, 2, 1, 3])
        doc.sendBackward([1])
        XCTAssertEqual(ids(doc.nodes), [0, 1, 2, 3])
        doc.bringToFront([0, 1])
        XCTAssertEqual(ids(doc.nodes), [2, 3, 0, 1])
        doc.sendToBack([0, 1])
        XCTAssertEqual(ids(doc.nodes), [0, 1, 2, 3])
        // Edges stay put.
        doc.bringForward([3])
        XCTAssertEqual(ids(doc.nodes), [0, 1, 2, 3])
        doc.sendBackward([0])
        XCTAssertEqual(ids(doc.nodes), [0, 1, 2, 3])
        // Contiguous selected runs keep their order when stepping.
        doc.bringForward([0, 1])
        XCTAssertEqual(ids(doc.nodes), [2, 0, 1, 3])
    }

    func testZOrderInsideGroups() {
        var doc = GraphicDocument(viewBox: ViewBox(width: 100, height: 100))
        doc.nodes = [
            .group(GroupNode(id: 10, children: [shape(0), shape(1), shape(2)])), shape(3),
        ]
        doc.bringToFront([0])
        guard case .group(let g) = doc.nodes[0] else { return XCTFail() }
        XCTAssertEqual(ids(g.children), [1, 2, 0])
        XCTAssertEqual(doc.nodes[1].id, 3)  // siblings elsewhere untouched
    }

    func testGroupWrapsSiblingsAtTopmostPosition() {
        var doc = GraphicDocument(viewBox: ViewBox(width: 100, height: 100))
        doc.nodes = [shape(0), shape(1), shape(2), shape(3)]
        guard let gid = doc.groupNodes([1, 3]) else { return XCTFail() }
        XCTAssertEqual(gid, 4)  // nextNodeID
        XCTAssertEqual(ids(doc.nodes), [0, 2, 4])
        guard case .group(let g) = doc.nodes[2] else { return XCTFail() }
        XCTAssertEqual(ids(g.children), [1, 3])  // document order kept
    }

    func testUngroupComposesTransformAndInheritsStyle() {
        var child = ShapeNode(
            id: 0, kind: .rect(x: 0, y: 0, width: 10, height: 10, rx: nil, ry: nil),
            transform: TransformValue(raw: "translate(1 2)", matrix: [1, 0, 0, 1, 1, 2]))
        child.style.opacity = 0.5
        var groupStyle = Style()
        groupStyle.fill = .color(r: 10, g: 20, b: 30)
        groupStyle.opacity = 0.5
        let group = GroupNode(
            id: 9, style: groupStyle,
            transform: TransformValue(raw: "scale(2)", matrix: [2, 0, 0, 2, 0, 0]),
            children: [.shape(child)])
        var doc = GraphicDocument(viewBox: ViewBox(width: 100, height: 100))
        doc.nodes = [.group(group)]
        let freed = doc.ungroupNodes([9])
        XCTAssertEqual(freed, [0])
        guard case .shape(let s) = doc.nodes[0] else { return XCTFail() }
        // scale(2) ∘ translate(1 2) = matrix(2 0 0 2 2 4).
        XCTAssertEqual(s.transform!.matrix, [2, 0, 0, 2, 2, 4])
        // Group fill inherited (child had none); opacity multiplied.
        XCTAssertEqual(s.effectiveStyle.fill, .color(r: 10, g: 20, b: 30))
        XCTAssertEqual(s.style.opacity!, 0.25, accuracy: 1e-9)
        // A point maps the same before and after: (3, 4) → group·child.
        let mapped = s.transform!.apply(Pt(3, 4))
        XCTAssertEqual(mapped.x, 8, accuracy: 1e-9)
        XCTAssertEqual(mapped.y, 12, accuracy: 1e-9)
    }

    func testUngroupWithoutTransformKeepsChildrenInPlace() {
        var doc = GraphicDocument(viewBox: ViewBox(width: 100, height: 100))
        doc.nodes = [shape(0), .group(GroupNode(id: 5, children: [shape(1), shape(2)])), shape(3)]
        let freed = doc.ungroupNodes([5])
        XCTAssertEqual(freed, [1, 2])
        XCTAssertEqual(ids(doc.nodes), [0, 1, 2, 3])
        guard case .shape(let s) = doc.nodes[1] else { return XCTFail() }
        XCTAssertNil(s.transform)
    }
}
