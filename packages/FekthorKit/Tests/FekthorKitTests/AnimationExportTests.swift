import XCTest

@testable import FekthorKit

final class AnimationExportTests: XCTestCase {

    /// A two-shape icon; `animated` binds spin to the circle and draw to
    /// the line, with the style block already baked (as saved sources are).
    private func icon(animated: Bool) -> GraphicDocument {
        var doc = GraphicDocument.blank(width: 24, height: 24)
        doc.nodes.append(
            .shape(
                ShapeNode(
                    id: 0, kind: .circle(center: Pt(12, 12), r: 8),
                    style: SVGStyle.parse("fill: none; stroke: #010101; stroke-width: 2;"))))
        doc.nodes.append(
            .shape(
                ShapeNode(
                    id: 1, kind: .line(Pt(2, 22), Pt(22, 22)),
                    style: SVGStyle.parse("stroke: #010101; stroke-width: 2;"))))
        guard animated else { return doc }
        doc = AnimationEngine.bind(
            AnimationPresets.spin, toNodes: [0], in: doc, settings: AnimationSettings())
        doc = AnimationEngine.bind(
            AnimationPresets.draw, trigger: "hover", toNodes: [1], in: doc,
            settings: AnimationSettings())
        return AnimationEngine.applyingStyleBlock(to: doc, workspace: nil)
    }

    func testActionParsingAndAliases() throws {
        XCTAssertEqual(try ExportAction.parse("strip-animations"), .stripAnimations)
        XCTAssertEqual(try ExportAction.parse("static"), .stripAnimations)
        XCTAssertEqual(try ExportAction.parse("bake-animations"), .bakeAnimations)
        XCTAssertEqual(try ExportAction.parse("animated"), .bakeAnimations)
        XCTAssertThrowsError(try ExportAction.parse("static:everything"))
    }

    func testStripAnimationsMatchesNeverAnimatedExport() throws {
        let profile = Workfile.ExportProfile(name: "static", actions: ["strip-animations"])
        let animated = try ExportRunner.apply(
            profile: profile, to: icon(animated: true), name: "loader")
        let never = try ExportRunner.apply(
            profile: Workfile.ExportProfile(name: "static", actions: []),
            to: icon(animated: false), name: "loader")
        XCTAssertEqual(
            SVGWriter.write(animated.document), SVGWriter.write(never.document),
            "a stripped export must byte-equal a never-animated one")
    }

    func testDefaultPolicyBakesEnabledIcons() throws {
        let profile = Workfile.ExportProfile(name: "plain", actions: [])
        let out = try ExportRunner.apply(
            profile: profile, to: icon(animated: true), name: "loader")
        let svg = SVGWriter.write(out.document)
        XCTAssertTrue(svg.contains("<style id=\"fekthor-animations\">"))
        XCTAssertTrue(svg.contains("class=\"fk-anim-spin\""))
        XCTAssertFalse(svg.contains("fekthor-meta"), "deliverables never carry the meta block")
    }

    func testDefaultPolicyStripsDisabledIcons() throws {
        var doc = icon(animated: true)
        var meta = FileMeta.read(from: doc)!
        meta.animationsEnabled = false
        doc = FileMeta.writing(meta, to: doc)
        let out = try ExportRunner.apply(
            profile: Workfile.ExportProfile(name: "plain", actions: []), to: doc,
            name: "loader")
        let svg = SVGWriter.write(out.document)
        XCTAssertFalse(svg.contains("fekthor-animations"))
        XCTAssertFalse(svg.contains("fk-anim-"))
    }

    func testBakeRunsLastOverPostActionReality() throws {
        // bake listed FIRST but the runner defers it: the recolor must land
        // inside the final document while the block still compiles.
        let profile = Workfile.ExportProfile(
            name: "web", actions: ["bake-animations", "recolor:#010101=currentColor"])
        let out = try ExportRunner.apply(
            profile: profile, to: icon(animated: true), name: "loader")
        let svg = SVGWriter.write(out.document)
        XCTAssertTrue(svg.contains("currentColor"))
        XCTAssertFalse(svg.contains("#010101"))
        // No workspace passed → file-local def → icon-scoped keyframes.
        XCTAssertTrue(svg.contains("@keyframes fk-loader-spin"))
        XCTAssertFalse(svg.contains("fekthor-meta"))
    }

    func testFlattenPreservesAnimationBoundGroups() throws {
        var doc = GraphicDocument.blank(width: 24, height: 24)
        var group = GroupNode(id: 0)
        group.children = [
            .shape(
                ShapeNode(
                    id: 1, kind: .rect(x: 4, y: 4, width: 8, height: 8, rx: nil, ry: nil),
                    style: SVGStyle.parse("fill: #010101;"))),
            .shape(
                ShapeNode(
                    id: 2, kind: .circle(center: Pt(16, 16), r: 4),
                    style: SVGStyle.parse("fill: #010101;"))),
        ]
        doc.nodes.append(.group(group))
        doc = AnimationEngine.bind(
            AnimationPresets.pulse, toNodes: [0], in: doc, settings: AnimationSettings())

        let out = try ExportRunner.apply(
            profile: Workfile.ExportProfile(name: "flat", actions: ["flatten"]), to: doc,
            name: "badge")
        let svg = SVGWriter.write(out.document)
        XCTAssertTrue(
            svg.contains("<g class=\"fk-anim-pulse\">"),
            "the bound group must survive flatten as the CSS hook:\n\(svg)")
        // No workspace passed → the def is file-local → icon-scoped name.
        XCTAssertTrue(svg.contains("@keyframes fk-badge-pulse"))

        // Without the binding, the same flatten dissolves the group.
        let plain = try ExportRunner.apply(
            profile: Workfile.ExportProfile(name: "flat", actions: ["flatten"]),
            to: {
                var d = doc
                d = AnimationEngine.unbind(target: "fk-anim-pulse", in: d)
                return d
            }(), name: "badge")
        XCTAssertFalse(SVGWriter.write(plain.document).contains("<g"))
    }

    func testStripAnimationsRemovesDrawPathLength() throws {
        let out = try ExportRunner.apply(
            profile: Workfile.ExportProfile(name: "static", actions: ["static"]),
            to: icon(animated: true), name: "loader")
        XCTAssertFalse(SVGWriter.write(out.document).contains("pathLength"))
    }
}
