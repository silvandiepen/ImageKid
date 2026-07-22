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
}
