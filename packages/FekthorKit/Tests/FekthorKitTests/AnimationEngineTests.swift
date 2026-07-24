import XCTest

@testable import FekthorKit

final class AnimationEngineTests: XCTestCase {

    private func doc() -> GraphicDocument {
        var doc = GraphicDocument.blank(width: 24, height: 24)
        doc.nodes.append(
            .shape(
                ShapeNode(
                    id: 0, kind: .circle(center: Pt(12, 12), r: 8),
                    style: SVGStyle.parse("fill: none; stroke: #010101;"))))
        doc.nodes.append(
            .shape(
                ShapeNode(
                    id: 1, kind: .line(Pt(2, 2), Pt(22, 22)),
                    style: SVGStyle.parse("stroke: #010101;"))))
        return doc
    }

    private func classes(_ doc: GraphicDocument, id: Int) -> [String] {
        guard let shape = doc.firstShape(id: id) else { return [] }
        return shape.attributes.extras.first { $0.name == "class" }?
            .value.split(separator: " ").map(String.init) ?? []
    }

    func testBindAddsClassBindingAndDefCopy() {
        let bound = AnimationEngine.bind(
            AnimationPresets.spin, trigger: "hover", toNodes: [0], in: doc(),
            settings: AnimationSettings())
        XCTAssertEqual(classes(bound, id: 0), ["fk-anim-spin"])
        XCTAssertEqual(classes(bound, id: 1), [])
        let meta = FileMeta.read(from: bound)
        XCTAssertEqual(meta?.animationBindings?.count, 1)
        XCTAssertEqual(meta?.animationBindings?.first?.trigger, "hover")
        XCTAssertEqual(meta?.animations?.first?.name, "spin")
        XCTAssertEqual(AnimationEngine.boundNodeIDs(in: bound, target: "fk-anim-spin"), [0])
    }

    func testBindSecondNodeJoinsExistingBinding() {
        var d = AnimationEngine.bind(
            AnimationPresets.spin, toNodes: [0], in: doc(), settings: AnimationSettings())
        d = AnimationEngine.bind(
            AnimationPresets.spin, toNodes: [1], in: d, settings: AnimationSettings())
        XCTAssertEqual(FileMeta.read(from: d)?.animationBindings?.count, 1)
        XCTAssertEqual(AnimationEngine.boundNodeIDs(in: d, target: "fk-anim-spin"), [0, 1])
    }

    func testBindWholeIconUsesRootClass() {
        let bound = AnimationEngine.bind(
            AnimationPresets.pulse, toNodes: [], in: doc(), settings: AnimationSettings())
        XCTAssertTrue(AnimationEngine.isWholeIcon("fk-anim-pulse", in: bound))
        XCTAssertEqual(AnimationEngine.boundNodeIDs(in: bound, target: "fk-anim-pulse"), [])
        // The root class survives the writer/reader round trip.
        let svg = SVGWriter.write(bound)
        XCTAssertTrue(svg.contains("class=\"fk-anim-pulse\""))
    }

    func testDrawBindingManagesPathLength() {
        var d = AnimationEngine.bind(
            AnimationPresets.draw, toNodes: [1], in: doc(), settings: AnimationSettings())
        XCTAssertTrue(
            d.firstShape(id: 1)!.attributes.extras
                .contains { $0.name == "pathLength" && $0.value == "100" })
        d = AnimationEngine.unbind(target: "fk-anim-draw", in: d)
        XCTAssertFalse(d.firstShape(id: 1)!.attributes.extras.contains { $0.name == "pathLength" })
    }

    func testUnbindRemovesEverything() {
        var d = AnimationEngine.bind(
            AnimationPresets.spin, toNodes: [0], in: doc(), settings: AnimationSettings())
        d = AnimationEngine.unbind(target: "fk-anim-spin", in: d)
        XCTAssertEqual(classes(d, id: 0), [])
        XCTAssertNil(FileMeta.read(from: d))
        XCTAssertFalse(SVGWriter.write(AnimationEngine.applyingStyleBlock(to: d, workspace: nil))
            .contains("fekthor-animations"))
    }

    func testUnbindKeepsDefWhileOtherBindingUsesIt() {
        // Two bindings of the same def can't share a target in v1, but a
        // def can be referenced by a manually-forked binding; simulate one.
        var d = AnimationEngine.bind(
            AnimationPresets.spin, toNodes: [0], in: doc(), settings: AnimationSettings())
        var meta = FileMeta.read(from: d)!
        meta.animationBindings?.append(
            AnimationBinding(animation: "spin", target: "fk-anim-spin-2"))
        d = FileMeta.writing(meta, to: d)
        d = AnimationEngine.unbind(target: "fk-anim-spin", in: d)
        XCTAssertEqual(FileMeta.read(from: d)?.animations?.first?.name, "spin")
        XCTAssertEqual(FileMeta.read(from: d)?.animationBindings?.count, 1)
    }

    func testBoundIconSavesAndPlaysEndToEnd() throws {
        // The full authoring loop: bind → save (style block bakes) →
        // reopen → binding still editable, block regenerates identically.
        let bound = AnimationEngine.bind(
            AnimationPresets.spin, toNodes: [0], in: doc(), settings: AnimationSettings())
        let svg = SVGWriter.write(
            AnimationEngine.applyingStyleBlock(to: bound, workspace: nil))
        XCTAssertTrue(svg.contains("@keyframes fk-spin"))
        XCTAssertTrue(svg.contains("class=\"fk-anim-spin\""))
        let reread = try SVGReader.read(svg)
        XCTAssertEqual(FileMeta.read(from: reread)?.animationBindings?.count, 1)
        let again = SVGWriter.write(
            AnimationEngine.applyingStyleBlock(to: reread, workspace: nil))
        XCTAssertEqual(again, svg)
    }
}
