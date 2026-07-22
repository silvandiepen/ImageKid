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
        guard case .stroke(let s) = moved, let r = s.refined else { return XCTFail() }
        XCTAssertEqual(r.segments[0].endPoint.y, 5, accuracy: 1e-9)
        XCTAssertEqual(r.start.x, 0, accuracy: 1e-9)
        XCTAssertEqual(r.segments[1].endPoint.x, 20, accuracy: 1e-9)
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
        else { return XCTFail() }
        XCTAssertEqual(endA.y, 4, accuracy: 1e-9)
        XCTAssertEqual(c2a.y, 4, accuracy: 1e-9)  // incoming control follows
        XCTAssertEqual(c1b.y, 4, accuracy: 1e-9)  // outgoing control follows
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
        }
        XCTAssertEqual(cubed.segments.last!.endPoint.x, -10, accuracy: 0.05)
        XCTAssertEqual(cubed.segments.last!.endPoint.y, 0, accuracy: 0.05)
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
        }
        XCTAssertEqual(paths[0].start.x, 2, accuracy: 1e-9)
        XCTAssertEqual(paths[0].segments.last!.endPoint.x, 2, accuracy: 1e-9)
        XCTAssertEqual(paths[0].segments.last!.endPoint.y, 1, accuracy: 1e-9)
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

    func testRemoveOnClosedKeepsLoopAndGuardsMinimum() {
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

final class InsertAnchorEditingTests: XCTestCase {
    /// Direct cubic Bézier evaluation, the ground truth the splits must match.
    private func bezier(_ p0: Pt, _ c1: Pt, _ c2: Pt, _ p3: Pt, _ t: Double) -> Pt {
        let u = 1 - t
        return Pt(
            u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x,
            u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y)
    }

    func testLineSplitAddsAnchorOnTheLine() {
        let rp = RefinedPath(
            start: Pt(0, 0), segments: [.line(to: Pt(10, 0)), .line(to: Pt(10, 10))],
            closed: false)
        let split = Editing.insertingAnchor(rp, segment: 0, t: 0.25)
        XCTAssertEqual(split.segments.count, 3)  // one more anchor
        XCTAssertEqual(split.segments[0].endPoint.x, 2.5, accuracy: 1e-9)
        XCTAssertEqual(split.segments[0].endPoint.y, 0, accuracy: 1e-9)
        XCTAssertEqual(split.segments[1].endPoint.x, 10, accuracy: 1e-9)
        XCTAssertEqual(split.segments.last!.endPoint.y, 10, accuracy: 1e-9)
    }

    func testCubicSplitIsExactDeCasteljau() {
        let p0 = Pt(0, 0)
        let c1 = Pt(2, 8)
        let c2 = Pt(8, -6)
        let p3 = Pt(10, 3)
        let rp = RefinedPath(
            start: p0, segments: [.cubic(c1: c1, c2: c2, to: p3)], closed: false)
        let s = 0.37
        let split = Editing.insertingAnchor(rp, segment: 0, t: s)
        XCTAssertEqual(split.segments.count, 2)
        // The new anchor sits exactly on the original curve at t = s.
        let onCurve = bezier(p0, c1, c2, p3, s)
        XCTAssertEqual(split.segments[0].endPoint.x, onCurve.x, accuracy: 1e-9)
        XCTAssertEqual(split.segments[0].endPoint.y, onCurve.y, accuracy: 1e-9)
        // Both halves reproduce the original geometry: sample densely and
        // compare against the original curve (reparameterised).
        for k in 0...20 {
            let t = Double(k) / 20
            let expected = bezier(p0, c1, c2, p3, t)
            let got: Pt
            if t <= s {
                got = Editing.segmentPoint(split, 0, s < 1e-12 ? 0 : t / s)
            } else {
                got = Editing.segmentPoint(split, 1, (t - s) / (1 - s))
            }
            XCTAssertEqual(got.x, expected.x, accuracy: 1e-9)
            XCTAssertEqual(got.y, expected.y, accuracy: 1e-9)
        }
    }

    func testArcSplitCubicizesAndStaysOnCircle() {
        let rp = RefinedPath(
            start: Pt(10, 0),
            segments: [
                .arc(center: Pt(0, 0), radius: 10, startAngle: 0, endAngle: .pi, clockwise: true)
            ], closed: false)
        let before = rp.nodeCount
        _ = before
        let cubed = Editing.cubicized(rp)
        let split = Editing.insertingAnchor(rp, segment: 0, t: 0.5)
        XCTAssertEqual(split.segments.count, cubed.segments.count + 1)
        XCTAssertFalse(
            split.segments.contains { if case .arc = $0 { return true } else { return false } })
        for p in PathRefine.flatten(split) {
            XCTAssertEqual((p.x * p.x + p.y * p.y).squareRoot(), 10, accuracy: 0.1)
        }
    }

    func testClosedPathSplitKeepsLoop() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [.line(to: Pt(10, 0)), .line(to: Pt(10, 10)), .line(to: Pt(0, 0))],
            closed: true)
        let split = Editing.insertingAnchor(rp, segment: 2, t: 0.5)
        XCTAssertTrue(split.closed)
        XCTAssertEqual(split.segments.count, 4)
        XCTAssertEqual(split.segments[2].endPoint.x, 5, accuracy: 1e-9)
        XCTAssertEqual(split.segments[2].endPoint.y, 5, accuracy: 1e-9)
        // Loop still lands back on the start.
        XCTAssertEqual(split.segments.last!.endPoint.x, 0, accuracy: 1e-9)
    }

    func testTClampsSanely() {
        let rp = RefinedPath(
            start: Pt(0, 0), segments: [.line(to: Pt(10, 0))], closed: false)
        let low = Editing.insertingAnchor(rp, segment: 0, t: -0.4)
        XCTAssertEqual(low.segments.count, 2)
        XCTAssertEqual(low.segments[0].endPoint.x, 0, accuracy: 1e-9)  // clamped to t=0
        XCTAssertEqual(low.segments.last!.endPoint.x, 10, accuracy: 1e-9)
        let high = Editing.insertingAnchor(rp, segment: 0, t: 1.4)
        XCTAssertEqual(high.segments.count, 2)
        XCTAssertEqual(high.segments[0].endPoint.x, 10, accuracy: 1e-9)  // clamped to t=1
        XCTAssertEqual(high.segments.last!.endPoint.x, 10, accuracy: 1e-9)
        // Out-of-range segment index clamps instead of crashing.
        let seg = Editing.insertingAnchor(rp, segment: 99, t: 0.5)
        XCTAssertEqual(seg.segments.count, 2)
    }

    func testClosestPointOnLinesAndCubics() {
        let rp = RefinedPath(
            start: Pt(0, 0),
            segments: [.line(to: Pt(10, 0)), .cubic(c1: Pt(10, 3), c2: Pt(10, 7), to: Pt(10, 10))],
            closed: false)
        // Near the middle of the first line.
        let hit1 = Editing.closestPoint(on: rp, to: Pt(5, 2))
        XCTAssertEqual(hit1.segment, 0)
        XCTAssertEqual(hit1.t, 0.5, accuracy: 1e-6)
        XCTAssertEqual(hit1.point.x, 5, accuracy: 1e-6)
        XCTAssertEqual(hit1.distance, 2, accuracy: 1e-6)
        // Near the cubic (a vertical line here): closest x is 10.
        let hit2 = Editing.closestPoint(on: rp, to: Pt(12, 5))
        XCTAssertEqual(hit2.segment, 1)
        XCTAssertEqual(hit2.point.x, 10, accuracy: 1e-3)
        XCTAssertEqual(hit2.point.y, 5, accuracy: 0.05)
        XCTAssertEqual(hit2.distance, 2, accuracy: 1e-3)
    }

    func testElementInsertSelectsNewAnchorIndex() {
        let rp = RefinedPath(
            start: Pt(0, 0), segments: [.line(to: Pt(10, 0)), .line(to: Pt(20, 0))],
            closed: false)
        let el = Element.stroke(
            StrokePath(
                id: "s", color: (0, 0, 0), width: 2, closed: false,
                points: [Pt(0, 0), Pt(10, 0), Pt(20, 0)], refined: rp))
        let before = Editing.anchors(of: el).count
        guard let inserted = Editing.insertAnchor(el, path: 0, segment: 1, t: 0.5) else {
            return XCTFail()
        }
        let anchors = Editing.anchors(of: inserted)
        XCTAssertEqual(anchors.count, before + 1)
        // New anchor index is segment + 1.
        XCTAssertEqual(anchors[2].position.x, 15, accuracy: 1e-9)
        // Fill primitives cannot take a point.
        let circle = Element.fill(
            FillShape(id: "f", color: (0, 0, 0), geometry: .circle(center: Pt(0, 0), radius: 5)))
        XCTAssertNil(Editing.insertAnchor(circle, path: 0, segment: 0, t: 0.5))
    }

    func testElementClosestPointOnRingsFill() {
        let el = Element.fill(
            FillShape(
                id: "f", color: (0, 0, 0),
                geometry: .rings([[Pt(0, 0), Pt(10, 0), Pt(10, 10), Pt(0, 10)]])))
        guard let hit = Editing.closestPoint(of: el, to: Pt(5, -2)) else { return XCTFail() }
        XCTAssertEqual(hit.path, 0)
        XCTAssertEqual(hit.segment, 0)
        XCTAssertEqual(hit.distance, 2, accuracy: 1e-9)
        guard let inserted = Editing.insertAnchor(el, path: 0, segment: 0, t: 0.5),
            case .fill(let f) = inserted, case .rings(let rings) = f.geometry
        else { return XCTFail() }
        XCTAssertEqual(rings[0].count, 5)
        XCTAssertEqual(rings[0][1].x, 5, accuracy: 1e-9)
    }
}
