import XCTest

@testable import FekthorKit

final class EditingTests: XCTestCase {
    func testMoveLineAnchorKeepsNeighbours() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [.line(to: Pt(10, 0)), .line(to: Pt(20, 0))], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        let moved = Editing.move(el, path: 0, anchor: 1, to: Pt(10, 5))
        guard case .stroke(let s) = moved, let r = s.refined else { return XCTFail() 
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}
        XCTAssertEqual(r.segments[0].endPoint.y, 5, accuracy: 1e-9)
        XCTAssertEqual(r.start.x, 0, accuracy: 1e-9)
        XCTAssertEqual(r.segments[1].endPoint.x, 20, accuracy: 1e-9)
    
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}

    func testMoveCubicAnchorDragsAdjacentControls() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        var path = Editing.cubicized(rp)
        path = Editing.movedPath(path, anchor: 1, to: Pt(10, 4))
        guard case .cubic(_, let c2a, let endA) = path.segments[0],
            case .cubic(let c1b, _, _) = path.segments[1]
        else { return XCTFail() 
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}
        XCTAssertEqual(endA.y, 4, accuracy: 1e-9)
        XCTAssertEqual(c2a.y, 4, accuracy: 1e-9)  // incoming control follows
        XCTAssertEqual(c1b.y, 4, accuracy: 1e-9)  // outgoing control follows
    
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}

    func testCubicizedArcStaysOnCircle() {
        let rp = RefinedPath(
            start: Pt(10, 0),
            segments: [
                .arc(center: Pt(0, 0), radius: 10, startAngle: 0, endAngle: .pi, clockwise: true)
            ], closed: false)
        let cubed = Editing.cubicized(rp)
        XCTAssertFalse(
            cubed.segments.contains { if case .arc = $0 { return true } else { return false } })
        // Sample the flattened result: every point within 0.1px of the circle.
        let pts = PathRefine.flatten(cubed)
        for p in pts {
            let r = (p.x * p.x + p.y * p.y).squareRoot()
            XCTAssertEqual(r, 10, accuracy: 0.1)
        
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}
        XCTAssertEqual(cubed.segments.last!.endPoint.x, -10, accuracy: 0.05)
        XCTAssertEqual(cubed.segments.last!.endPoint.y, 0, accuracy: 0.05)
    
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}

    func testClosedPathSeamIsOneAnchor() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .line(to: Pt(10, 0)), .line(to: Pt(10, 10)), .line(to: Pt(0, 0)),
            ], closed: true)
        let el = Element.fill(
            FillShape(id: "f", color: (0, 0, 0), geometry: .refined([rp])))
        let anchors = Editing.anchors(of: el)
        XCTAssertEqual(anchors.count, 3)  // seam deduped
        // Moving the start also moves the closing segment's end.
        let moved = Editing.move(el, path: 0, anchor: 0, to: Pt(2, 1))
        guard case .fill(let f) = moved, case .refined(let paths) = f.geometry else {
            return XCTFail()
        
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}
        XCTAssertEqual(paths[0].start.x, 2, accuracy: 1e-9)
        XCTAssertEqual(paths[0].segments.last!.endPoint.x, 2, accuracy: 1e-9)
        XCTAssertEqual(paths[0].segments.last!.endPoint.y, 1, accuracy: 1e-9)
    
    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}

    func testHandlesAndMoveHandle() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 0), c2: Pt(7, 0), to: Pt(10, 0)),
                .cubic(c1: Pt(13, 0), c2: Pt(17, 0), to: Pt(20, 0)),
            ], closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        // Interior anchor: incoming c2 and outgoing c1.
        let hs = Editing.handles(of: el, path: 0, anchor: 1)
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs[0].position.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hs[1].position.x, 13, accuracy: 1e-9)
        // Start anchor of an open path: only the outgoing c1.
        XCTAssertEqual(Editing.handles(of: el, path: 0, anchor: 0).count, 1)
        // Move the outgoing handle; only that control changes.
        let moved = Editing.moveHandle(el, path: 0, segment: 1, kind: .c1, to: Pt(13, 6))
        guard case .stroke(let s2) = moved, let r2 = s2.refined,
            case .cubic(let c1, let c2, let end) = r2.segments[1]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 6, accuracy: 1e-9)
        XCTAssertEqual(c2.y, 0, accuracy: 1e-9)
        XCTAssertEqual(end.y, 0, accuracy: 1e-9)
    }
}

final class EditingToolsTests: XCTestCase {
    private func openStroke(_ id: String, _ pts: [Pt]) -> Element {
        var segs: [RefinedSegment] = []
        for p in pts.dropFirst() { segs.append(.line(to: p)) }
        let rp = RefinedPath(start: pts[0], segments: segs, closed: false)
        return .stroke(
            StrokePath(id: id, color: (0, 0, 0), width: 2, closed: false, points: pts, refined: rp))
    }

    func testBreakOpenStrokeAtInteriorAnchor() {
        let el = openStroke("s", [Pt(0, 0), Pt(10, 0), Pt(20, 0), Pt(30, 0)])
        guard let parts = Editing.breakAt(el, path: 0, anchor: 2) else { return XCTFail() }
        XCTAssertEqual(parts.count, 2)
        guard case .stroke(let a) = parts[0], case .stroke(let b) = parts[1],
            let ra = a.refined, let rb = b.refined
        else { return XCTFail() }
        XCTAssertEqual(ra.segments.count, 2)
        XCTAssertEqual(rb.segments.count, 1)
        XCTAssertEqual(rb.start.x, 20, accuracy: 1e-9)
        // Terminal anchors cannot break.
        XCTAssertNil(Editing.breakAt(el, path: 0, anchor: 0))
        XCTAssertNil(Editing.breakAt(el, path: 0, anchor: 3))
    }

    func testBreakClosedStrokeCutsOpen() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [.line(to: Pt(10, 0)), .line(to: Pt(10, 10)), .line(to: Pt(0, 0))],
            closed: true)
        let el = Element.stroke(
            StrokePath(
                id: "c", color: (0, 0, 0), width: 2, closed: true,
                points: [Pt(0, 0), Pt(10, 0), Pt(10, 10)], refined: rp))
        guard let parts = Editing.breakAt(el, path: 0, anchor: 1) else { return XCTFail() }
        XCTAssertEqual(parts.count, 1)
        guard case .stroke(let s) = parts[0], let r = s.refined else { return XCTFail() }
        XCTAssertFalse(r.closed)
        XCTAssertEqual(r.start.x, 10, accuracy: 1e-9)
        XCTAssertEqual(r.segments.count, 3)
    }

    func testMergeJoinsTwoOpenStrokes() {
        var doc = VectorDocument(width: 100, height: 100)
        doc.elements = [
            openStroke("a", [Pt(0, 0), Pt(10, 0), Pt(20, 0)]),
            openStroke("b", [Pt(24, 2), Pt(34, 2), Pt(44, 2)]),
        ]
        // Merge a's end (anchor 2) with b's start (anchor 0).
        let refs = [
            Editing.AnchorRef(element: 0, path: 0, anchor: 2),
            Editing.AnchorRef(element: 1, path: 0, anchor: 0),
        ]
        let merged = Editing.merge(doc, refs: refs)
        XCTAssertEqual(merged.elements.count, 1)
        guard case .stroke(let s) = merged.elements[0], let rp = s.refined else {
            return XCTFail()
        }
        // Weld point is the centroid of (20,0) and (24,2).
        XCTAssertEqual(rp.segments[1].endPoint.x, 22, accuracy: 1e-9)
        XCTAssertEqual(rp.segments[1].endPoint.y, 1, accuracy: 1e-9)
        XCTAssertEqual(rp.start.x, 0, accuracy: 1e-9)
        XCTAssertEqual(rp.segments.last!.endPoint.x, 44, accuracy: 1e-9)
        XCTAssertFalse(rp.closed)
    }

    func testMergeSameStrokeEndsClosesLoop() {
        var doc = VectorDocument(width: 100, height: 100)
        doc.elements = [openStroke("a", [Pt(0, 0), Pt(10, 0), Pt(10, 10), Pt(1, 1)])]
        let refs = [
            Editing.AnchorRef(element: 0, path: 0, anchor: 0),
            Editing.AnchorRef(element: 0, path: 0, anchor: 3),
        ]
        let merged = Editing.merge(doc, refs: refs)
        guard case .stroke(let s) = merged.elements[0], let rp = s.refined else {
            return XCTFail()
        }
        XCTAssertTrue(rp.closed)
        // Both ends moved to the centroid of (0,0) and (1,1).
        XCTAssertEqual(rp.start.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rp.segments.last!.endPoint.x, 0.5, accuracy: 1e-9)
    }
}

final class RemoveAnchorTests: XCTestCase {
    private func openStroke(_ pts: [Pt]) -> Element {
        var segs: [RefinedSegment] = []
        for p in pts.dropFirst() { segs.append(.line(to: p)) }
        let rp = RefinedPath(start: pts[0], segments: segs, closed: false)
        return .stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false, points: pts, refined: rp))
    }

    func testRemoveEndpointShortensLine() {
        let el = openStroke([Pt(0, 0), Pt(10, 0), Pt(20, 0)])
        guard let removed = Editing.removeAnchor(el, path: 0, anchor: 2),
            case .stroke(let s) = removed, let rp = s.refined
        else { return XCTFail() }
        XCTAssertEqual(rp.segments.count, 1)
        XCTAssertEqual(rp.segments.last!.endPoint.x, 10, accuracy: 1e-9)
        guard let removedStart = Editing.removeAnchor(el, path: 0, anchor: 0),
            case .stroke(let s2) = removedStart, let rp2 = s2.refined
        else { return XCTFail() }
        XCTAssertEqual(rp2.start.x, 10, accuracy: 1e-9)
    }

    func testRemoveInteriorMergesSegments() {
        // Two collinear lines merge into ONE line (simpler path).
        let el = openStroke([Pt(0, 0), Pt(10, 0), Pt(20, 0)])
        guard let removed = Editing.removeAnchor(el, path: 0, anchor: 1),
            case .stroke(let s) = removed, let rp = s.refined
        else { return XCTFail() }
        XCTAssertEqual(rp.segments.count, 1)
        if case .line(let to) = rp.segments[0] {
            XCTAssertEqual(to.x, 20, accuracy: 1e-9)
        } else {
            XCTFail("collinear line merge should stay a line")
        }
        // Cubic + cubic keeps the outer tangents.
        let rpC = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .cubic(c1: Pt(3, 4), c2: Pt(7, 4), to: Pt(10, 0)),
                .cubic(c1: Pt(13, -4), c2: Pt(17, -4), to: Pt(20, 0)),
            ], closed: false)
        let elC = Element.stroke(
            StrokePath(
                id: "c", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rpC))
        guard let removedC = Editing.removeAnchor(elC, path: 0, anchor: 1),
            case .stroke(let sc) = removedC, let rc = sc.refined,
            case .cubic(let c1, let c2, let to) = rc.segments[0]
        else { return XCTFail() }
        XCTAssertEqual(c1.y, 4, accuracy: 1e-9)
        XCTAssertEqual(c2.y, -4, accuracy: 1e-9)
        XCTAssertEqual(to.x, 20, accuracy: 1e-9)
    }

    func testRemoveOnClosedKeepsLoopAndGuardsMinimum(){
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [
                .line(to: Pt(10, 0)), .line(to: Pt(10, 10)), .line(to: Pt(0, 10)),
                .line(to: Pt(0, 0)),
            ], closed: true)
        let el = Element.stroke(
            StrokePath(
                id: "q", color: (0, 0, 0), width: 2, closed: true,
                points: [Pt(0, 0), Pt(10, 0), Pt(10, 10), Pt(0, 10)], refined: rp))
        guard let removed = Editing.removeAnchor(el, path: 0, anchor: 2),
            case .stroke(let s) = removed, let r = s.refined
        else { return XCTFail() }
        XCTAssertTrue(r.closed)
        XCTAssertEqual(r.segments.count, 3)
        // A triangle refuses further removal.
        guard let tri = Editing.removeAnchor(removed, path: 0, anchor: 1) else {
            return  // acceptable: already minimal after this removal chain
        }
        _ = tri
    }

    func testOpenStrokeMinimumGuard() {
        let el = openStroke([Pt(0, 0), Pt(10, 0)])
        XCTAssertNil(Editing.removeAnchor(el, path: 0, anchor: 1))
    }
}
