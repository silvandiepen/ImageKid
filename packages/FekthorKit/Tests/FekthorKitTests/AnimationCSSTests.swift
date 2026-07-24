import XCTest

@testable import FekthorKit

final class AnimationCSSTests: XCTestCase {

    // The spin/draw/gated fixture from docs/fekthor/ANIMATIONS.md.
    private var fixtureDefs: [AnimationDef] {
        [AnimationPresets.spin, AnimationPresets.draw, AnimationPresets.pulse]
    }

    private var fixtureBindings: [AnimationBinding] {
        [
            AnimationBinding(animation: "spin", target: "fk-anim-spin", trigger: "continuous"),
            AnimationBinding(animation: "draw", target: "fk-anim-draw", trigger: "hover"),
            AnimationBinding(
                animation: "pulse", target: "fk-anim-pulse", trigger: "parent-class:panel-live"),
        ]
    }

    private func compileFixture(settings: AnimationSettings = AnimationSettings()) -> String? {
        AnimationCSS.compile(
            defs: fixtureDefs, bindings: fixtureBindings, settings: settings,
            iconSlug: "spinner-check", workspaceDefNames: ["spin", "draw", "pulse"])
    }

    private func fixtureDocument() -> GraphicDocument {
        var doc = GraphicDocument.blank(width: 24, height: 24)
        var circle = ShapeNode(
            id: 0, kind: .circle(center: Pt(12, 12), r: 8),
            style: SVGStyle.parse("fill: none; stroke: #010101; stroke-width: 2;"))
        circle.attributes.extras = [XMLAttr(name: "class", value: "fk-anim-spin")]
        doc.nodes.append(.shape(circle))
        let meta = FileMeta.Meta(
            animations: fixtureDefs, animationBindings: fixtureBindings)
        return FileMeta.writing(meta, to: doc)
    }

    private func firstShape(in doc: GraphicDocument) -> ShapeNode? {
        func find(_ nodes: [GraphicNode]) -> ShapeNode? {
            for node in nodes {
                switch node {
                case .shape(let s): return s
                case .group(let g):
                    if let hit = find(g.children) { return hit }
                case .raw: break
                }
            }
            return nil
        }
        return find(doc.nodes)
    }

    private func golden() throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "Fixtures/animations/golden-block", withExtension: "css")
                ?? Bundle.module.url(
                    forResource: "animations/golden-block", withExtension: "css",
                    subdirectory: "Fixtures"))
        var text = try String(contentsOf: url, encoding: .utf8)
        if text.hasSuffix("\n") { text.removeLast() }
        return text
    }

    // MARK: - Golden output

    func testFixtureCompilesToGoldenBlock() throws {
        XCTAssertEqual(compileFixture(), try golden())
    }

    func testCompileIsDeterministic() {
        XCTAssertEqual(compileFixture(), compileFixture())
    }

    func testCompileReturnsNilWithoutUsableBindings() {
        XCTAssertNil(
            AnimationCSS.compile(
                defs: fixtureDefs, bindings: [], settings: AnimationSettings(),
                iconSlug: nil, workspaceDefNames: []))
        // A binding referencing an unknown def compiles to nothing.
        XCTAssertNil(
            AnimationCSS.compile(
                defs: [], bindings: fixtureBindings, settings: AnimationSettings(),
                iconSlug: nil, workspaceDefNames: []))
    }

    // MARK: - Namespacing

    func testWorkspaceDefsCompileByteIdenticallyAcrossIcons() {
        let a = AnimationCSS.compile(
            defs: [AnimationPresets.spin],
            bindings: [AnimationBinding(animation: "spin", target: "fk-anim-spin")],
            settings: AnimationSettings(), iconSlug: "icon-a", workspaceDefNames: ["spin"])
        let b = AnimationCSS.compile(
            defs: [AnimationPresets.spin],
            bindings: [AnimationBinding(animation: "spin", target: "fk-anim-spin")],
            settings: AnimationSettings(), iconSlug: "icon-b", workspaceDefNames: ["spin"])
        XCTAssertEqual(a, b)
        XCTAssertTrue(a?.contains("@keyframes fk-spin {") == true)
    }

    func testFileLocalDefsCompileIconScoped() {
        let css = AnimationCSS.compile(
            defs: [AnimationPresets.spin],
            bindings: [AnimationBinding(animation: "spin", target: "fk-anim-spin")],
            settings: AnimationSettings(), iconSlug: "loader", workspaceDefNames: [])
        XCTAssertTrue(css?.contains("@keyframes fk-loader-spin {") == true)
        XCTAssertTrue(css?.contains("animation-name: fk-loader-spin;") == true)
        // Consumer custom properties keep the CONSUMER-facing name.
        XCTAssertTrue(css?.contains("--icon-animate-spin-duration") == true)
    }

    func testPrefixSettingsRespected() {
        let css = AnimationCSS.compile(
            defs: [AnimationPresets.spin],
            bindings: [AnimationBinding(animation: "spin", target: "ik-anim-spin")],
            settings: AnimationSettings(
                classPrefix: "ik-", triggerClassPrefix: "play",
                customPropertyPrefix: "ik-anim"),
            iconSlug: nil, workspaceDefNames: ["spin"])
        XCTAssertTrue(css?.contains("@keyframes ik-spin {") == true)
        XCTAssertTrue(css?.contains(".play-hover:hover .ik-anim-spin") == true)
        XCTAssertTrue(css?.contains("var(--ik-anim-duration, .8s)") == true)
        XCTAssertFalse(css?.contains("--icon-animate") == true)
    }

    func testReducedMotionIgnoreDropsMediaWrapper() {
        let css = compileFixture(settings: AnimationSettings(reducedMotion: "ignore"))
        XCTAssertFalse(css?.contains("@media") == true)
        XCTAssertTrue(css?.contains("animation-name: fk-spin;") == true)
    }

    // MARK: - Document surgery + round-trip

    func testApplyingStyleBlockWritesFirstNodeAndRoundTripsByteIdentically() throws {
        let doc = AnimationEngine.applyingStyleBlock(
            to: fixtureDocument(), workspace: nil, iconSlug: "spinner-check")
        guard case .raw(let raw) = doc.nodes.first else {
            return XCTFail("style block should be the first node")
        }
        XCTAssertTrue(AnimationCSS.isAnimXML(raw.xml))

        let svg = SVGWriter.write(doc)
        XCTAssertTrue(svg.contains("<style id=\"fekthor-animations\">"))
        // Passthrough: read → write is byte-identical.
        let reread = try SVGReader.read(svg)
        XCTAssertEqual(SVGWriter.write(reread), svg)
        // Recompile-on-save: read → re-apply → write is byte-identical too.
        let reapplied = AnimationEngine.applyingStyleBlock(
            to: reread, workspace: nil, iconSlug: "spinner-check")
        XCTAssertEqual(SVGWriter.write(reapplied), svg)
    }

    func testGeneratedBlockDoesNotPolluteClassStyle() throws {
        let svg = SVGWriter.write(
            AnimationEngine.applyingStyleBlock(
                to: fixtureDocument(), workspace: nil, iconSlug: nil))
        let reread = try SVGReader.read(svg)
        guard let shape = firstShape(in: reread) else {
            return XCTFail("shape missing")
        }
        XCTAssertNil(shape.classStyle, "generated CSS must never resolve into classStyle")
    }

    func testForeignStyleBlockStillResolvesAndSurvives() throws {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <style>.brand { fill: #ff0000; }</style>
              <rect class="brand" x="2" y="2" width="20" height="20"/>
            </svg>
            """
        let doc = try SVGReader.read(svg)
        XCTAssertNotNil(firstShape(in: doc)?.classStyle)
        let stripped = AnimationCSS.removing(from: doc)
        XCTAssertTrue(
            stripped.nodes.contains {
                if case .raw(let raw) = $0 { return raw.xml.contains(".brand") }
                return false
            }, "foreign style blocks are never Fekthor's to remove")
    }

    func testDisabledIconRemovesBlock() {
        var doc = fixtureDocument()
        var meta = FileMeta.read(from: doc)!
        meta.animationsEnabled = false
        doc = FileMeta.writing(meta, to: doc)
        let applied = AnimationEngine.applyingStyleBlock(to: doc, workspace: nil)
        XCTAssertFalse(SVGWriter.write(applied).contains("fekthor-animations"))
    }

    func testWorkspaceSettingsFlowThroughApplyingStyleBlock() {
        var workfile = Workfile()
        workfile.animations = [AnimationPresets.spin]
        workfile.settings = Workfile.WorkspaceSettings(
            animations: AnimationSettings(defaultDuration: 3))
        var doc = GraphicDocument.blank(width: 24, height: 24)
        // Binding only — the def copy comes from the workspace.
        doc = FileMeta.writing(
            FileMeta.Meta(
                animationBindings: [AnimationBinding(animation: "spin", target: "fk-anim-spin")]),
            to: doc)
        let svg = SVGWriter.write(
            AnimationEngine.applyingStyleBlock(to: doc, workspace: workfile, iconSlug: "a"))
        // Def timing (.8s) still wins over the workspace default…
        XCTAssertTrue(svg.contains("var(--icon-animate-duration, .8s)"))
        XCTAssertTrue(svg.contains("@keyframes fk-spin {"))
        // …but a def without its own duration picks the workspace default up.
        workfile.animations = [
            AnimationDef(
                name: "spin",
                keyframes: AnimationPresets.spin.keyframes)
        ]
        let svg2 = SVGWriter.write(
            AnimationEngine.applyingStyleBlock(to: doc, workspace: workfile, iconSlug: "a"))
        XCTAssertTrue(svg2.contains("var(--icon-animate-duration, 3s)"))
    }
}
