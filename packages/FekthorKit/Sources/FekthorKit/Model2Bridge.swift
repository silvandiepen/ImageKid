import Foundation

/// One-way mapping from the trace pipeline's output (`VectorDocument`) into
/// the editor model (`GraphicDocument`). Lossless: geometry stays typed,
/// primitives stay primitives (rotation becomes a transform), gradients
/// carry over, and stroke attributes land in the style declaration list.
/// The trace pipeline never consumes Model2 — this bridge is the only
/// crossing point.
public enum Model2Bridge {
    public static func graphicDocument(from doc: VectorDocument) -> GraphicDocument {
        var out = GraphicDocument(
            viewBox: ViewBox(width: Double(doc.width), height: Double(doc.height)),
            rootAttributes: [XMLAttr(name: "xmlns", value: "http://www.w3.org/2000/svg")],
            hadXMLDeclaration: false, nodes: [])
        var nextID = 0
        for element in doc.elements {
            switch element {
            case .fill(let f):
                out.nodes.append(.shape(fillNode(f, id: nextID)))
            case .stroke(let s):
                out.nodes.append(.shape(strokeNode(s, id: nextID)))
            }
            nextID += 1
        }
        return out
    }

    static func fillNode(_ f: FillShape, id: Int) -> ShapeNode {
        var style = Style()
        switch f.paint {
        case .solid(let c):
            style.set(
                "fill",
                .paint(
                    .color(
                        r: c.count > 0 ? c[0] : 0, g: c.count > 1 ? c[1] : 0,
                        b: c.count > 2 ? c[2] : 0)))
        case .linear(let g):
            style.set("fill", .paint(.linear(g)))
        case .radial(let g):
            style.set("fill", .paint(.radial(g)))
        }

        let kind: ShapeKind
        var transform: TransformValue? = nil
        switch f.geometry {
        case .refined(let paths):
            kind = .path(paths)
            style.set("fill-rule", .keyword("evenodd"))
        case .rings(let rings):
            // Exact polygonal representation — no smoothing at the bridge.
            var paths: [RefinedPath] = []
            for ring in rings where ring.count >= 3 {
                var segments: [RefinedSegment] = []
                for p in ring.dropFirst() { segments.append(.line(to: p)) }
                paths.append(RefinedPath(start: ring[0], segments: segments, closed: true))
            }
            kind = .path(paths)
            style.set("fill-rule", .keyword("evenodd"))
        case .circle(let c, let r):
            kind = .circle(center: c, r: r)
        case .ellipse(let c, let rx, let ry, let rotation):
            kind = .ellipse(center: c, rx: rx, ry: ry)
            transform = rotationTransform(rotation, about: c)
        case .rect(let c, let w, let h, let rotation, let cornerRadius):
            kind = .rect(
                x: c.x - w / 2, y: c.y - h / 2, width: w, height: h,
                rx: cornerRadius > 0.01 ? cornerRadius : nil, ry: nil)
            transform = rotationTransform(rotation, about: c)
        }
        return ShapeNode(
            id: id, kind: kind, style: style,
            attributes: NodeAttributes(svgID: f.id.isEmpty ? nil : f.id),
            transform: transform)
    }

    static func strokeNode(_ s: StrokePath, id: Int) -> ShapeNode {
        var style = Style()
        style.set("fill", .paint(.none))
        style.set(
            "stroke",
            .paint(
                .color(
                    r: s.color.count > 0 ? s.color[0] : 0,
                    g: s.color.count > 1 ? s.color[1] : 0,
                    b: s.color.count > 2 ? s.color[2] : 0)))
        style.set("stroke-width", .number(s.width, unit: nil))
        style.set("stroke-linecap", .keyword(capName(s.cap)))
        style.set("stroke-linejoin", .keyword("round"))

        let path: RefinedPath
        if let rp = s.refined {
            path = rp
        } else {
            var segments: [RefinedSegment] = []
            for p in s.points.dropFirst() { segments.append(.line(to: p)) }
            path = RefinedPath(
                start: s.points.first ?? Pt(0, 0), segments: segments, closed: s.closed)
        }
        return ShapeNode(
            id: id, kind: .path([path]), style: style,
            attributes: NodeAttributes(svgID: s.id.isEmpty ? nil : s.id))
    }

    static func capName(_ cap: LineCap) -> String {
        switch cap {
        case .round: return "round"
        case .butt: return "butt"
        case .square: return "square"
        }
    }

    static func rotationTransform(_ radians: Double, about c: Pt) -> TransformValue? {
        guard abs(radians) > 1e-9 else { return nil }
        let deg = radians * 180 / .pi
        let cosA = cos(radians)
        let sinA = sin(radians)
        // rotate(deg cx cy) == translate(cx,cy) rotate(deg) translate(-cx,-cy)
        let tx = c.x - cosA * c.x + sinA * c.y
        let ty = c.y - sinA * c.x - cosA * c.y
        let degText = String(format: "%.4f", deg)
        let cxText = String(format: "%.2f", c.x)
        let cyText = String(format: "%.2f", c.y)
        return TransformValue(
            raw: "rotate(\(degText) \(cxText) \(cyText))",
            matrix: [cosA, sinA, -sinA, cosA, tx, ty])
    }
}
