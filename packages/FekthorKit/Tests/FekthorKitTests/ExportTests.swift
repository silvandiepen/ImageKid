import XCTest

@testable import FekthorKit

/// P2 export-profile engine: action grammar, per-action document transforms,
/// stroke outlining (validated by render comparison), and an acceptance test
/// that reproduces the open-icon library build on real corpus files.
final class ExportTests: XCTestCase {
    // MARK: - Helpers

    func doc(_ nodes: [GraphicNode], size: Double = 72) -> GraphicDocument {
        GraphicDocument(
            viewBox: ViewBox(width: size, height: size),
            rootAttributes: [XMLAttr(name: "xmlns", value: "http://www.w3.org/2000/svg")],
            nodes: nodes)
    }

    func style(_ text: String) -> Style { SVGStyle.parse(text) }

    func onlyShape(_ d: GraphicDocument, _ index: Int = 0) -> ShapeNode {
        var shapes: [ShapeNode] = []
        func walk(_ nodes: [GraphicNode]) {
            for n in nodes {
                switch n {
                case .shape(let s): shapes.append(s)
                case .group(let g): walk(g.children)
                case .raw, .image: break
                }
            }
        }
        walk(d.nodes)
        return shapes[index]
    }

    /// Shoelace area of a ring path (absolute).
    func ringArea(_ rp: RefinedPath) -> Double {
        let pts = PathRefine.flatten(rp)
        var a = 0.0
        for i in 0..<pts.count {
            let p = pts[i]
            let q = pts[(i + 1) % pts.count]
            a += p.x * q.y - q.x * p.y
        }
        return abs(a) / 2
    }

    func bounds(_ rp: RefinedPath) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let pts = PathRefine.flatten(rp)
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for p in pts {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        return (minX, minY, maxX, maxY)
    }

    /// Reference render of a GraphicDocument through the trace-model
    /// Rasterizer (flatten first; fills even-odd, strokes real-width with
    /// round joins). var()/currentColor paints render via their fallbacks.
    func rasterize(_ d: GraphicDocument, scale: Double = 4) -> RasterImage {
        let flat = ExportAction.flatten.applied(to: d)
        var elements: [Element] = []
        var i = 0
        for node in flat.nodes {
            guard case .shape(let s) = node, case .path(let paths) = s.kind else { continue }
            let st = s.effectiveStyle
            if let fill = st.fill, let c = fill.renderColor {
                elements.append(
                    .fill(
                        FillShape(
                            id: "f\(i)", color: (c.r, c.g, c.b), geometry: .refined(paths))))
            }
            if let stroke = st.stroke, let c = stroke.renderColor {
                let w = st.strokeWidth ?? 1
                var cap = LineCap.butt
                if case .keyword(let k)? = st.value(of: "stroke-linecap"),
                    let parsed = LineCap(rawValue: k)
                {
                    cap = parsed
                }
                for (j, rp) in paths.enumerated() {
                    elements.append(
                        .stroke(
                            StrokePath(
                                id: "s\(i)-\(j)", color: (c.r, c.g, c.b), width: w,
                                closed: rp.closed, points: PathRefine.flatten(rp),
                                cap: cap, refined: rp)))
                }
            }
            i += 1
        }
        let vd = VectorDocument(
            width: Int(flat.viewBox.width.rounded()),
            height: Int(flat.viewBox.height.rounded()), elements: elements)
        return Rasterizer.render(vd, smoothing: 1, scale: scale)
    }

    func fixture(_ name: String) throws -> GraphicDocument {
        guard
            let dir = Bundle.module.url(forResource: "Fixtures/openicon-lib", withExtension: nil)
                ?? Bundle.module.url(
                    forResource: "openicon-lib", withExtension: nil, subdirectory: "Fixtures"),
            let text = try? String(
                contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
        else {
            throw XCTSkip("fixture \(name) missing")
        }
        return try SVGReader.read(text)
    }

    // MARK: - Grammar

    func testParseActions() throws {
        XCTAssertEqual(try ExportAction.parse("outline-strokes"), .outlineStrokes)
        XCTAssertEqual(try ExportAction.parse(" Flatten "), .flatten)
        XCTAssertEqual(try ExportAction.parse("strip-ids"), .stripIDs)
        XCTAssertEqual(try ExportAction.parse("strip"), .stripIDs)
        XCTAssertEqual(try ExportAction.parse("resize:24x24"), .resize(width: 24, height: 24))
        XCTAssertEqual(try ExportAction.parse("fit:32"), .resize(width: 32, height: 32))
        XCTAssertEqual(
            try ExportAction.parse("recolor:#010101=var(--icon-color, #010101)"),
            .recolor(scope: .both, from: "#010101", to: .paint("var(--icon-color, #010101)")))
        XCTAssertEqual(
            try ExportAction.parse("recolor:stroke:#231f20=remove"),
            .recolor(scope: .stroke, from: "#231f20", to: .remove))
        XCTAssertEqual(
            try ExportAction.parse("recolor:fill:none=#fff"),
            .recolor(scope: .fill, from: "none", to: .paint("#fff")))
        XCTAssertEqual(
            try ExportAction.parse("stroke-width:2"), .strokeWidth(.set(value: 2, unit: nil)))
        XCTAssertEqual(
            try ExportAction.parse("stroke-width:2px"),
            .strokeWidth(.set(value: 2, unit: "px")))
        XCTAssertEqual(
            try ExportAction.parse("stroke-width:x1.5"), .strokeWidth(.scale(1.5)))
        XCTAssertEqual(
            try ExportAction.parse("stroke-width:4px=var(--w, 5)"),
            .strokeWidth(.map(value: 4, unit: "px", to: "var(--w, 5)")))
        XCTAssertEqual(
            try ExportAction.parse("restyle:opacity:.5=var(--o, 1)"),
            .restyle(property: "opacity", match: ".5", value: "var(--o, 1)"))
        XCTAssertEqual(
            try ExportAction.parse("restyle:opacity:*="),
            .restyle(property: "opacity", match: nil, value: nil))
    }

    func testParseErrors() {
        XCTAssertThrowsError(try ExportAction.parse("vectorize")) { error in
            XCTAssertEqual(error as? ExportActionError, .unknownAction("vectorize"))
        }
        XCTAssertThrowsError(try ExportAction.parse("resize:axb")) { error in
            guard case .malformedAction? = error as? ExportActionError else {
                return XCTFail("expected malformedAction, got \(error)")
            }
        }
        XCTAssertThrowsError(try ExportAction.parse("resize"))
        XCTAssertThrowsError(try ExportAction.parse("recolor:#010101"))
        XCTAssertThrowsError(try ExportAction.parse("stroke-width:huge"))
        XCTAssertThrowsError(try ExportAction.parse(""))
        XCTAssertThrowsError(try ExportAction.parse("flatten:hard"))
    }

    // MARK: - recolor

    func testRecolorToVarExactText() throws {
        let d = doc([
            .shape(
                ShapeNode(
                    id: 0, kind: .rect(x: 0, y: 0, width: 10, height: 10, rx: nil, ry: nil),
                    style: style("fill: #ed2024; opacity: .5;")))
        ])
        let out = try ExportAction.parse("recolor:fill:#ed2024=var(--icon-fill, rgba(0, 0, 0, 0))")
            .applied(to: d)
        let text = SVGWriter.write(out)
        XCTAssertTrue(
            text.contains("fill: var(--icon-fill, rgba(0, 0, 0, 0)); opacity: .5;"),
            "got: \(text)")
        XCTAssertEqual(SVGWriter.write(d), SVGWriter.write(doc(d.nodes)), "input untouched")
    }

    func testRecolorRemoveAndScope() throws {
        let d = doc([
            .shape(
                ShapeNode(
                    id: 0, kind: .line(Pt(0, 0), Pt(10, 0)),
                    style: style("fill: #231f20; stroke: #231f20; stroke-width: 4px;")))
        ])
        let out = try ExportAction.parse("recolor:stroke:#231f20=remove").applied(to: d)
        let s = onlyShape(out)
        XCTAssertNil(s.style.stroke)
        XCTAssertEqual(s.style.fill, .color(r: 0x23, g: 0x1f, b: 0x20), "fill scope untouched")
        XCTAssertEqual(s.style.strokeWidth, 4)
    }

    func testRecolorHexAndCurrentColor() throws {
        let d = doc([
            .shape(
                ShapeNode(
                    id: 0, kind: .circle(center: Pt(5, 5), r: 3),
                    style: style("fill: #010101; stroke: currentColor;")))
        ])
        var out = try ExportAction.parse("recolor:#010101=#fff").applied(to: d)
        XCTAssertEqual(onlyShape(out).style.fill, .color(r: 255, g: 255, b: 255))
        out = try ExportAction.parse("recolor:currentColor=#010101").applied(to: out)
        XCTAssertEqual(onlyShape(out).style.stroke, .color(r: 1, g: 1, b: 1))
    }

    // MARK: - stroke-width

    func testStrokeWidthSetScaleMap() throws {
        let d = doc([
            .shape(
                ShapeNode(
                    id: 0, kind: .line(Pt(0, 0), Pt(10, 0)),
                    style: style("stroke: #010101; stroke-width: 4px;")))
        ])
        var s = onlyShape(try ExportAction.parse("stroke-width:2").applied(to: d))
        XCTAssertEqual(s.style.value(of: "stroke-width"), .number(2, unit: "px"), "unit kept")

        s = onlyShape(try ExportAction.parse("stroke-width:x1.5").applied(to: d))
        XCTAssertEqual(s.style.value(of: "stroke-width"), .number(6, unit: "px"))

        s = onlyShape(try ExportAction.parse("stroke-width:4px=var(--w, 5)").applied(to: d))
        XCTAssertEqual(s.style.value(of: "stroke-width"), .raw("var(--w, 5)"))

        // Non-matching width is untouched by map.
        s = onlyShape(try ExportAction.parse("stroke-width:2px=var(--w, 5)").applied(to: d))
        XCTAssertEqual(s.style.value(of: "stroke-width"), .number(4, unit: "px"))
    }

    // MARK: - restyle

    func testRestyle() throws {
        let d = doc([
            .shape(
                ShapeNode(
                    id: 0, kind: .circle(center: Pt(5, 5), r: 3),
                    style: style("fill: #ed2024; opacity: .5;"))),
            .shape(
                ShapeNode(
                    id: 1, kind: .circle(center: Pt(9, 9), r: 3),
                    style: style("fill: #ed2024; opacity: .8;"))),
        ])
        let out = try ExportAction.parse("restyle:opacity:.5=var(--icon-fill-opacity, 1)")
            .applied(to: d)
        XCTAssertEqual(
            onlyShape(out, 0).style.value(of: "opacity"), .raw("var(--icon-fill-opacity, 1)"))
        XCTAssertEqual(onlyShape(out, 1).style.value(of: "opacity"), .number(0.8, unit: nil))

        let cleared = try ExportAction.parse("restyle:opacity:*=").applied(to: d)
        XCTAssertNil(onlyShape(cleared, 0).style.value(of: "opacity"))
        XCTAssertNil(onlyShape(cleared, 1).style.value(of: "opacity"))
    }

    // MARK: - flatten

    func testFlattenTransformedGroup() throws {
        let group = GroupNode(
            id: 0, style: style("fill: #ff0000;"),
            transform: SVGReader.parseTransform("translate(10 5)"),
            children: [
                .shape(
                    ShapeNode(
                        id: 1, kind: .rect(x: 0, y: 0, width: 10, height: 10, rx: nil, ry: nil))),
                .shape(
                    ShapeNode(
                        id: 2, kind: .line(Pt(1, 2), Pt(3, 4)),
                        style: style("fill: #00ff00;"),
                        transform: SVGReader.parseTransform("scale(2)"))),
            ])
        let out = ExportAction.flatten.applied(to: doc([.group(group)]))

        XCTAssertEqual(out.nodes.count, 2, "group dissolved")
        let rect = onlyShape(out, 0)
        guard case .path(let rectPaths) = rect.kind else { return XCTFail("not a path") }
        XCTAssertNil(rect.transform)
        XCTAssertEqual(rectPaths[0].start, Pt(10, 5), "transform baked")
        XCTAssertTrue(rectPaths[0].closed)
        XCTAssertEqual(rect.style.fill, .color(r: 255, g: 0, b: 0), "group style merged")

        let line = onlyShape(out, 1)
        guard case .path(let linePaths) = line.kind else { return XCTFail("not a path") }
        XCTAssertEqual(linePaths[0].start, Pt(12, 9), "composed transform: scale then translate")
        XCTAssertEqual(linePaths[0].segments, [.line(to: Pt(16, 13))])
        XCTAssertEqual(line.style.fill, .color(r: 0, g: 255, b: 0), "child style wins")
    }

    // MARK: - resize

    func testResize() throws {
        let d = doc([
            .shape(
                ShapeNode(
                    id: 0, kind: .line(Pt(18, 36), Pt(54, 36)),
                    style: style("fill: none; stroke: #010101; stroke-width: 4px;"))),
            .shape(
                ShapeNode(
                    id: 1, kind: .rect(x: 9, y: 9, width: 54, height: 54, rx: 3, ry: nil),
                    style: style("stroke-width:var(--w, 4);"))),
        ])
        let out = try ExportAction.parse("resize:144x144").applied(to: d)
        XCTAssertEqual(out.viewBox, ViewBox(minX: 0, minY: 0, width: 144, height: 144))
        let line = onlyShape(out, 0)
        guard case .line(let a, let b) = line.kind else { return XCTFail("line degraded") }
        XCTAssertEqual(a, Pt(36, 72))
        XCTAssertEqual(b, Pt(108, 72))
        XCTAssertEqual(line.style.value(of: "stroke-width"), .number(8, unit: "px"), "scaled")
        let rect = onlyShape(out, 1)
        guard case .rect(let x, let y, let w, let h, let rx, _) = rect.kind else {
            return XCTFail("rect degraded")
        }
        XCTAssertEqual([x, y, w, h, rx ?? -1], [18, 18, 108, 108, 6])
        XCTAssertEqual(
            rect.style.value(of: "stroke-width"), .raw("var(--w, 4)"), "raw width untouched")

        // Non-square target letterboxes: uniform scale, centered.
        let fit = try ExportAction.parse("resize:144x216").applied(to: d)
        let l2 = onlyShape(fit, 0)
        guard case .line(let a2, _) = l2.kind else { return XCTFail() }
        XCTAssertEqual(a2, Pt(36, 108), "centered vertically: +36 offset")
    }

    // MARK: - strip-ids

    func testStripIDs() throws {
        let d = doc([
            .group(
                GroupNode(
                    id: 0,
                    attributes: NodeAttributes(
                        svgID: "Layer_1",
                        extras: [XMLAttr(name: "data-name", value: "Layer 1")]),
                    children: [
                        .shape(
                            ShapeNode(
                                id: 1, kind: .circle(center: Pt(5, 5), r: 2),
                                attributes: NodeAttributes(
                                    svgID: "dot",
                                    extras: [
                                        XMLAttr(name: "class", value: "cls-1"),
                                        XMLAttr(name: "data-name", value: "dot"),
                                    ])))
                    ]))
        ])
        let out = ExportAction.stripIDs.applied(to: d)
        guard case .group(let g) = out.nodes[0] else { return XCTFail() }
        XCTAssertNil(g.attributes.svgID)
        XCTAssertTrue(g.attributes.extras.isEmpty)
        let s = onlyShape(out)
        XCTAssertNil(s.attributes.svgID)
        XCTAssertEqual(s.attributes.extras, [XMLAttr(name: "class", value: "cls-1")])
    }

    // MARK: - outline-strokes: silhouettes

    func testOutlineStraightLineButt() throws {
        let d = doc([
            .shape(
                ShapeNode(
                    id: 0, kind: .line(Pt(10, 20), Pt(50, 20)),
                    style: style("fill: none; stroke: #231f20; stroke-width: 4px;")))
        ])
        let out = ExportAction.outlineStrokes.applied(to: d)
        let s = onlyShape(out)
        guard case .path(let rings) = s.kind else { return XCTFail("not outlined") }
        XCTAssertEqual(rings.count, 1)
        XCTAssertTrue(rings[0].closed)
        XCTAssertEqual(ringArea(rings[0]), 160, accuracy: 1e-6, "40×4 rectangle")
        let bb = bounds(rings[0])
        XCTAssertEqual([bb.minX, bb.minY, bb.maxX, bb.maxY], [10, 18, 50, 22])
        XCTAssertEqual(s.style.fill, .color(r: 0x23, g: 0x1f, b: 0x20), "former stroke colour")
        XCTAssertNil(s.style.stroke)
        XCTAssertNil(s.style.strokeWidth)
    }

    func testOutlineStraightLineRoundCaps() throws {
        let d = doc([
            .shape(
                ShapeNode(
                    id: 0, kind: .line(Pt(10, 20), Pt(50, 20)),
                    style: style(
                        "fill: none; stroke: #231f20; stroke-width: 4px; stroke-linecap: round;")))
        ])
        let out = ExportAction.outlineStrokes.applied(to: d)
        guard case .path(let rings) = onlyShape(out).kind else { return XCTFail() }
        XCTAssertEqual(rings.count, 1)
        XCTAssertEqual(ringArea(rings[0]), 160 + .pi * 4, accuracy: 0.5, "capsule")
        let bb = bounds(rings[0])
        XCTAssertEqual(bb.minX, 8, accuracy: 0.1)
        XCTAssertEqual(bb.maxX, 52, accuracy: 0.1)
        XCTAssertEqual(bb.minY, 18, accuracy: 1e-9)
        XCTAssertEqual(bb.maxY, 22, accuracy: 1e-9)
    }

    func testOutlineLPolylineRoundJoin() throws {
        let d = doc([
            .shape(
                ShapeNode(
                    id: 0, kind: .polyline([Pt(10, 10), Pt(40, 10), Pt(40, 40)]),
                    style: style("fill: none; stroke: #010101; stroke-width: 4px;")))
        ])
        let out = ExportAction.outlineStrokes.applied(to: d)
        guard case .path(let rings) = onlyShape(out).kind else { return XCTFail() }
        XCTAssertEqual(rings.count, 1)
        // Two 30×4 bands, minus the 2×2 corner overlap, plus the quarter-disc
        // round join: 120 + 120 − 4 + π.
        XCTAssertEqual(ringArea(rings[0]), 236 + .pi, accuracy: 0.5)
        let bb = bounds(rings[0])
        XCTAssertEqual([bb.minX, bb.minY], [10, 8])
        XCTAssertEqual(bb.maxX, 42, accuracy: 0.05)
        XCTAssertEqual(bb.maxY, 40, accuracy: 1e-9)
    }

    func testOutlineClosedTriangleRingPair() throws {
        let d = doc([
            .shape(
                ShapeNode(
                    id: 0, kind: .polygon([Pt(20, 20), Pt(52, 20), Pt(36, 48)]),
                    style: style("fill: none; stroke: #010101; stroke-width: 4px;")))
        ])
        let out = ExportAction.outlineStrokes.applied(to: d)
        guard case .path(let rings) = onlyShape(out).kind else { return XCTFail() }
        XCTAssertEqual(rings.count, 2, "outer + inner ring")
        let areas = rings.map(ringArea).sorted()
        // Triangle: A = 448, P = 32 + 2·√1040.
        let perimeter = 32 + 2 * (1040.0).squareRoot()
        let outer = 448 + perimeter * 2 + .pi * 4  // round joins
        XCTAssertEqual(areas[1], outer, accuracy: 2)
        // Inner (mitered) offset: A − P·r + r²·Σ cot(θ/2) ≈ 275.8.
        XCTAssertEqual(areas[0], 275.8, accuracy: 2)
    }

    /// The real correctness test: rendering the stroked original and the
    /// outlined document must agree pixel-wise.
    func testOutlineRenderAgreementSynthetic() throws {
        let shapes: [(String, ShapeKind, String)] = [
            ("line-round",
             .line(Pt(10, 20), Pt(50, 20)),
             "fill: none; stroke: #010101; stroke-width: 4px; stroke-linecap: round;"),
            ("l-shape",
             .polyline([Pt(10, 10), Pt(40, 10), Pt(40, 40)]),
             "fill: none; stroke: #010101; stroke-width: 4px;"),
            ("triangle",
             .polygon([Pt(20, 20), Pt(52, 20), Pt(36, 48)]),
             "fill: none; stroke: #010101; stroke-width: 4px;"),
            ("circle",
             .circle(center: Pt(36, 36), r: 27),
             "fill: none; stroke: #010101; stroke-width: 4px;"),
        ]
        for (name, kind, css) in shapes {
            let d = doc([.shape(ShapeNode(id: 0, kind: kind, style: style(css)))])
            let outlined = ExportAction.outlineStrokes.applied(to: d)
            let metrics = Comparer.compare(rasterize(d), rasterize(outlined), tolerance: 24)
            XCTAssertGreaterThan(metrics.exactPct, 97, "\(name): \(metrics)")
        }
    }

    func testOutlineRenderAgreementRealIcons() throws {
        for name in ["add-m.src.svg", "shield.src.svg", "compass.src.svg"] {
            let d = try fixture(name)
            let outlined = ExportAction.outlineStrokes.applied(to: d)
            // Outlined docs must contain no stroked shapes anymore.
            func hasStroke(_ nodes: [GraphicNode]) -> Bool {
                for n in nodes {
                    if case .shape(let s) = n, let p = s.style.stroke {
                        if case PaintValue.none = p { continue }
                        return true
                    }
                    if case .group(let g) = n, hasStroke(g.children) { return true }
                }
                return false
            }
            XCTAssertFalse(hasStroke(outlined.nodes), name)
            let metrics = Comparer.compare(rasterize(d), rasterize(outlined), tolerance: 24)
            XCTAssertGreaterThan(metrics.exactPct, 97, "\(name): \(metrics)")
        }
    }

    // MARK: - Runner

    func testRunnerNamingAndBatch() throws {
        let profile = Workfile.ExportProfile(
            name: "web", actions: ["stroke-width:2"], output: "{name}-{profile}.svg")
        let a = doc([
            .shape(
                ShapeNode(
                    id: 0, kind: .line(Pt(0, 0), Pt(1, 1)),
                    style: style("stroke: #010101; stroke-width: 4px;")))
        ])
        let single = try ExportRunner.apply(profile: profile, to: a, name: "add-m")
        XCTAssertEqual(single.fileName, "add-m-web.svg")
        XCTAssertEqual(onlyShape(single.document).style.strokeWidth, 2)

        let results = try ExportRunner.run(profile: profile, over: ["b": a, "a": a, "c": a])
        XCTAssertEqual(results.map(\.fileName), ["a-web.svg", "b-web.svg", "c-web.svg"])

        // Default template.
        let bare = Workfile.ExportProfile(name: "p")
        XCTAssertEqual(try ExportRunner.apply(profile: bare, to: a, name: "x").fileName, "x.svg")
    }

    func testRunnerStripsFileMetadata() throws {
        // File-local swatches/styles ride inside the SVG as a metadata
        // block; deliverables must never carry it — even through a bare
        // profile with no actions.
        let source = FileMeta.writing(
            FileMeta.Meta(
                swatches: ["#ff0000"],
                styles: [NamedStyle(name: "brand", declarations: ["fill": "#ff0000"])]),
            to: doc([
                .shape(
                    ShapeNode(
                        id: 0, kind: .rect(x: 0, y: 0, width: 10, height: 10, rx: nil, ry: nil),
                        style: style("fill: #ff0000;")))
            ]))
        XCTAssertNotNil(FileMeta.read(from: source))
        let bare = Workfile.ExportProfile(name: "p")
        let exported = try ExportRunner.apply(profile: bare, to: source, name: "x").document
        XCTAssertNil(FileMeta.read(from: exported))
        XCTAssertFalse(SVGWriter.write(exported).contains("fekthor-meta"))
        // The source document itself is untouched (non-destructive runner).
        XCTAssertNotNil(FileMeta.read(from: source))
    }

    func testRunnerReportsUnknownAction() {
        let profile = Workfile.ExportProfile(name: "p", actions: ["flatten", "frobnicate:9"])
        let d = doc([])
        XCTAssertThrowsError(try ExportRunner.apply(profile: profile, to: d, name: "x")) { e in
            XCTAssertEqual(e as? ExportActionError, .unknownAction("frobnicate"))
        }
    }

    func testSafeFileNameNormalizes() throws {
        // Ordinary names and subfolders pass through.
        XCTAssertEqual(try ExportRunner.safeFileName("a.svg"), "a.svg")
        XCTAssertEqual(try ExportRunner.safeFileName("web/icons/a.svg"), "web/icons/a.svg")
        // Leading slashes strip (absolute → relative), `.` and doubled
        // slashes collapse, and interior `..` resolves lexically.
        XCTAssertEqual(try ExportRunner.safeFileName("/etc/a.svg"), "etc/a.svg")
        XCTAssertEqual(try ExportRunner.safeFileName("//x//a.svg"), "x/a.svg")
        XCTAssertEqual(try ExportRunner.safeFileName("./a.svg"), "a.svg")
        XCTAssertEqual(try ExportRunner.safeFileName("sub/../a.svg"), "a.svg")
        XCTAssertEqual(try ExportRunner.safeFileName("a/b/../../c.svg"), "c.svg")
    }

    func testSafeFileNameRejectsEscapesAndEmpty() {
        func expect(_ name: String, _ expected: ExportRunner.FileNameError) {
            XCTAssertThrowsError(try ExportRunner.safeFileName(name), name) { e in
                XCTAssertEqual(e as? ExportRunner.FileNameError, expected, name)
            }
        }
        // Climbing above the destination is never allowed — even when a
        // leading slash or `.` precedes the `..`.
        expect("../a.svg", .escapesDestination("../a.svg"))
        expect("a/../../b.svg", .escapesDestination("a/../../b.svg"))
        expect("/../a.svg", .escapesDestination("/../a.svg"))
        expect("./../a.svg", .escapesDestination("./../a.svg"))
        // Nothing left to write: empty, only separators, or a `..` chain
        // landing exactly on the destination directory itself.
        expect("", .empty)
        expect("/", .empty)
        expect(".", .empty)
        expect("a/..", .empty)
    }

    // MARK: - Acceptance: the open-icon library build

    /// Encode open-icon's real build (icon-components-v2 with the repo's
    /// build/config.json: simplifyColors + removeData + replaceData) as an
    /// export profile and check the result is semantically equivalent to the
    /// SHIPPED lib/icons files: same paints (including exact var() text),
    /// same stroke-widths, same opacity. Geometry byte-parity not required.
    func testAcceptanceOpenIconLibBuild() throws {
        let profile = Workfile.ExportProfile(
            name: "openicon-lib",
            actions: [
                "recolor:stroke:#231f20=remove",
                "recolor:stroke:#ed2024=var(--icon-stroke-color-secondary, var(--icon-stroke-color, currentColor))",
                "recolor:fill:#ed2024=var(--icon-fill, rgba(0, 0, 0, 0))",
                "restyle:opacity:.5=var(--icon-fill-opacity, 1)",
                "stroke-width:4px=var(--icon-stroke-width-m, calc(var(--icon-stroke-width, 5) * 1))",
            ],
            output: "{name}.svg")

        var sources: [String: GraphicDocument] = [:]
        for name in ["add-m", "shield", "compass"] {
            sources[name] = try fixture("\(name).src.svg")
        }
        let results = try ExportRunner.run(profile: profile, over: sources)
        XCTAssertEqual(results.map(\.fileName), ["add-m.svg", "compass.svg", "shield.svg"])

        func shapes(_ d: GraphicDocument) -> [ShapeNode] {
            var out: [ShapeNode] = []
            func walk(_ nodes: [GraphicNode]) {
                for n in nodes {
                    if case .shape(let s) = n { out.append(s) }
                    if case .group(let g) = n { walk(g.children) }
                }
            }
            walk(d.nodes)
            return out
        }
        func norm(_ v: StyleValue?) -> String? {
            guard let v else { return nil }
            return SVGStyle.valueText(v)
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .joined(separator: " ")
        }
        for (fileName, produced) in results {
            let name = String(fileName.dropLast(4))
            let expected = try fixture("\(name).lib.svg")
            let mine = shapes(produced)
            let libs = shapes(expected)
            XCTAssertEqual(mine.count, libs.count, "\(name): node count")
            for (m, l) in zip(mine, libs) {
                for prop in [
                    "fill", "stroke", "stroke-width", "opacity", "stroke-miterlimit",
                    "stroke-linecap",
                ] {
                    XCTAssertEqual(
                        norm(m.style.value(of: prop)), norm(l.style.value(of: prop)),
                        "\(name): \(prop)")
                }
            }
        }
    }
}
