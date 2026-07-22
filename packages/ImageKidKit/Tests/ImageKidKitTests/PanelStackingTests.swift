import XCTest

@testable import ImageKidKit

final class PanelStackingTests: XCTestCase {

    // MARK: - Attach / detach semantics

    func testAttachTwoSoloPanelsFormsAStack() {
        var stacks = PanelStacks()
        stacks.attach("b", below: "a")
        XCTAssertEqual(stacks.stacks, [["a", "b"]])
        XCTAssertTrue(stacks.isHead("a"))
        XCTAssertTrue(stacks.isFollower("b"))
    }

    func testAttachAppendsBelowTheTail() {
        var stacks = PanelStacks()
        stacks.attach("b", below: "a")
        stacks.attach("c", below: "b")
        XCTAssertEqual(stacks.stacks, [["a", "b", "c"]])
    }

    func testAttachInsertsDirectlyBelowTheTarget() {
        var stacks = PanelStacks(stacks: [["a", "c"]])
        stacks.attach("b", below: "a")
        XCTAssertEqual(stacks.stacks, [["a", "b", "c"]])
    }

    func testAttachBringsTheWholeChainAlong() {
        // Dragging head B of [B, C] under A moves both.
        var stacks = PanelStacks(stacks: [["b", "c"]])
        stacks.attach("b", below: "a")
        XCTAssertEqual(stacks.stacks, [["a", "b", "c"]])
    }

    func testAttachBelowOwnFollowerIsIgnored() {
        var stacks = PanelStacks(stacks: [["a", "b"]])
        stacks.attach("a", below: "b")
        XCTAssertEqual(stacks.stacks, [["a", "b"]])
    }

    func testAttachToSelfIsIgnored() {
        var stacks = PanelStacks()
        stacks.attach("a", below: "a")
        XCTAssertEqual(stacks.stacks, [])
    }

    func testDetachMiddleReattachesTheOnesBelow() {
        var stacks = PanelStacks(stacks: [["a", "b", "c"]])
        stacks.detach("b")
        XCTAssertEqual(stacks.stacks, [["a", "c"]])
        XCTAssertEqual(stacks.followers(of: "a"), ["c"])
    }

    func testDetachHeadPromotesTheNextPanel() {
        var stacks = PanelStacks(stacks: [["a", "b", "c"]])
        stacks.detach("a")
        XCTAssertEqual(stacks.stacks, [["b", "c"]])
        XCTAssertTrue(stacks.isHead("b"))
    }

    func testDetachFromPairDissolvesTheStack() {
        var stacks = PanelStacks(stacks: [["a", "b"]])
        stacks.detach("b")
        XCTAssertEqual(stacks.stacks, [])
        XCTAssertFalse(stacks.isStacked("a"))
    }

    func testDetachUnstackedPanelIsANoOp() {
        var stacks = PanelStacks(stacks: [["a", "b"]])
        stacks.detach("z")
        XCTAssertEqual(stacks.stacks, [["a", "b"]])
    }

    // MARK: - Queries

    func testFollowersAndHead() {
        let stacks = PanelStacks(stacks: [["a", "b", "c"]])
        XCTAssertEqual(stacks.followers(of: "a"), ["b", "c"])
        XCTAssertEqual(stacks.followers(of: "b"), ["c"])
        XCTAssertEqual(stacks.followers(of: "c"), [])
        XCTAssertEqual(stacks.followers(of: "z"), [])
        XCTAssertEqual(stacks.head(of: "c"), "a")
        XCTAssertNil(stacks.head(of: "z"))
        XCTAssertFalse(stacks.isHead("z"))
        XCTAssertFalse(stacks.isFollower("z"))
    }

    func testSingletonStacksAreDropped() {
        let stacks = PanelStacks(stacks: [["a"], ["b", "c"]])
        XCTAssertEqual(stacks.stacks, [["b", "c"]])
    }

    // MARK: - Snap detection

    private func frame(x: CGFloat, y: CGFloat, w: CGFloat = 240, h: CGFloat = 200) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    func testSnapCandidateWithinTolerance() {
        let stacks = PanelStacks()
        let dragged = frame(x: 100, y: 308)  // top edge 8pt below a's bottom
        let others = ["a": frame(x: 100, y: 100)]  // bottom edge at 300
        XCTAssertEqual(stacks.snapCandidate(for: "d", frame: dragged, others: others), "a")
    }

    func testSnapCandidateBeyondToleranceMisses() {
        let stacks = PanelStacks()
        let dragged = frame(x: 100, y: 330)  // 30pt gap
        let others = ["a": frame(x: 100, y: 100)]
        XCTAssertNil(stacks.snapCandidate(for: "d", frame: dragged, others: others))
    }

    func testSnapCandidateRespectsCustomTolerance() {
        let stacks = PanelStacks()
        let dragged = frame(x: 100, y: 330)
        let others = ["a": frame(x: 100, y: 100)]
        XCTAssertEqual(
            stacks.snapCandidate(for: "d", frame: dragged, others: others, tolerance: 40), "a")
    }

    func testSnapCandidateNeedsHalfHorizontalOverlap() {
        let stacks = PanelStacks()
        let dragged = frame(x: 100, y: 300)
        // Shifted 130 of 240pt: only 110pt overlap (< 120) — no stick.
        let barely = ["a": frame(x: 230, y: 100)]
        XCTAssertNil(stacks.snapCandidate(for: "d", frame: dragged, others: barely))
        // Shifted 110: 130pt overlap — sticks.
        let enough = ["a": frame(x: 210, y: 100)]
        XCTAssertEqual(stacks.snapCandidate(for: "d", frame: dragged, others: enough), "a")
    }

    func testSnapCandidateExcludesSelf() {
        let stacks = PanelStacks()
        let dragged = frame(x: 100, y: 300)
        let others = ["d": frame(x: 100, y: 100)]
        XCTAssertNil(stacks.snapCandidate(for: "d", frame: dragged, others: others))
    }

    func testSnapCandidateExcludesOwnFollowers() {
        // d drags its follower e along — e can't be its own stick target.
        let stacks = PanelStacks(stacks: [["d", "e"]])
        let dragged = frame(x: 100, y: 300)
        let others = ["e": frame(x: 100, y: 100)]
        XCTAssertNil(stacks.snapCandidate(for: "d", frame: dragged, others: others))
    }

    func testSnapCandidateExcludesPanelsWithSomethingAlreadyBelow() {
        // a already has b stuck below — only the stack's tail is a target.
        let stacks = PanelStacks(stacks: [["a", "b"]])
        let dragged = frame(x: 100, y: 300)
        let others = [
            "a": frame(x: 100, y: 100),
            "b": frame(x: 100, y: 100),
        ]
        XCTAssertEqual(stacks.snapCandidate(for: "d", frame: dragged, others: others), "b")
    }

    func testSnapCandidatePicksTheClosest() {
        let stacks = PanelStacks()
        let dragged = frame(x: 100, y: 300)
        let others = [
            "far": frame(x: 100, y: 90),  // bottom at 290, 10pt off
            "near": frame(x: 100, y: 96),  // bottom at 296, 4pt off
        ]
        XCTAssertEqual(stacks.snapCandidate(for: "d", frame: dragged, others: others), "near")
    }

    // MARK: - Layout

    func testLayoutStacksFlushWithZeroGap() {
        let origins = PanelStacks.layout(
            stack: ["a", "b", "c"],
            headOrigin: CGPoint(x: 40, y: 16),
            sizes: [
                "a": CGSize(width: 240, height: 200),
                "b": CGSize(width: 240, height: 120),
                "c": CGSize(width: 240, height: 180),
            ])
        XCTAssertEqual(origins["a"], CGPoint(x: 40, y: 16))
        XCTAssertEqual(origins["b"], CGPoint(x: 40, y: 216))
        XCTAssertEqual(origins["c"], CGPoint(x: 40, y: 336))
    }

    func testLayoutAlignsEveryMemberToTheHeadX() {
        let origins = PanelStacks.layout(
            stack: ["a", "b"],
            headOrigin: CGPoint(x: 300, y: 0),
            sizes: ["a": CGSize(width: 240, height: 150), "b": CGSize(width: 240, height: 90)])
        XCTAssertEqual(origins["b"]?.x, 300)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = PanelStacks(stacks: [["a", "b"], ["c", "d", "e"]])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PanelStacks.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDecodingDropsSingletonStacks() throws {
        let data = Data(#"{"stacks":[["a"],["b","c"]]}"#.utf8)
        let decoded = try JSONDecoder().decode(PanelStacks.self, from: data)
        XCTAssertEqual(decoded.stacks, [["b", "c"]])
    }
}
