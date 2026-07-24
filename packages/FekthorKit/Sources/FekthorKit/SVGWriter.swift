import Foundation

/// Deterministic SVG writer for `GraphicDocument`.
///
/// Contract (docs/fekthor/EDITOR-PLAN.md): output is deterministic (two
/// writes are byte-identical) and IDEMPOTENT — `write(read(write(read(f))))`
/// equals `write(read(f))`. Byte parity with arbitrary sources is not
/// promised (first save normalizes formatting); semantic equality is.
///
/// Conventions mirror the open-icon corpus: pretty-printed with two-space
/// indentation, inline `style` attributes in declaration order, primitives
/// kept as their native elements, numbers in corpus style (`SVGNum`), and
/// the XML declaration only when the source had one. Arcs become cubics by
/// default (`Options(emitArcs: true)` for trace-export parity).
public enum SVGWriter {
    public struct Options: Sendable {
        public var emitArcs: Bool
        public init(emitArcs: Bool = false) {
            self.emitArcs = emitArcs
        }
    }

    public static func write(_ doc: GraphicDocument, options: Options = Options()) -> String {
        var out = ""
        if doc.hadXMLDeclaration {
            out += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        }
        out += "<svg"
        for attr in doc.rootAttributes {
            out += " \(attr.name)=\"\(escapeAttr(attr.value))\""
        }
        out +=
            " viewBox=\"\(SVGNum.text(doc.viewBox.minX)) \(SVGNum.text(doc.viewBox.minY)) "
            + "\(SVGNum.text(doc.viewBox.width)) \(SVGNum.text(doc.viewBox.height))\">\n"

        // Gradient paints referenced by nodes get deterministic defs ids in
        // document order (same grad-N convention as the trace exporter).
        var gradientDefs: [String] = []
        var gradientIDs: [String] = []  // parallel: serialized def → id
        func gradientID(for paint: PaintValue) -> String? {
            let def: String
            switch paint {
            case .linear(let g):
                var s =
                    "<linearGradient id=\"@ID@\" gradientUnits=\"userSpaceOnUse\" "
                    + "x1=\"\(SVGNum.text(g.p0.x))\" y1=\"\(SVGNum.text(g.p0.y))\" "
                    + "x2=\"\(SVGNum.text(g.p1.x))\" y2=\"\(SVGNum.text(g.p1.y))\">"
                for stop in g.stops {
                    s += stopText(stop)
                }
                s += "</linearGradient>"
                def = s
            case .radial(let g):
                var s =
                    "<radialGradient id=\"@ID@\" gradientUnits=\"userSpaceOnUse\" "
                    + "cx=\"\(SVGNum.text(g.center.x))\" cy=\"\(SVGNum.text(g.center.y))\" "
                    + "r=\"\(SVGNum.text(g.radius))\">"
                for stop in g.stops {
                    s += stopText(stop)
                }
                s += "</radialGradient>"
                def = s
            default:
                return nil
            }
            if let idx = gradientDefs.firstIndex(of: def) {
                return gradientIDs[idx]
            }
            let id = "grad-\(gradientDefs.count)"
            gradientDefs.append(def)
            gradientIDs.append(id)
            return id
        }

        var body = ""
        func emit(_ nodes: [GraphicNode], indent: Int) {
            let pad = String(repeating: "  ", count: indent)
            for node in nodes {
                switch node {
                case .raw(let raw):
                    body += pad + raw.xml + "\n"
                case .group(let g):
                    body += pad + "<g"
                    body += nodeAttrText(g.attributes)
                    if let t = g.transform, !t.raw.isEmpty {
                        body += " transform=\"\(escapeAttr(t.raw))\""
                    }
                    if !g.style.declarations.isEmpty {
                        body += " style=\"\(escapeAttr(SVGStyle.serialize(g.style)))\""
                    }
                    body += ">\n"
                    emit(g.children, indent: indent + 1)
                    body += pad + "</g>\n"
                case .shape(let s):
                    body += pad + shapeText(s, gradientID: gradientID) + "\n"
                }
            }
        }
        emit(doc.nodes, indent: 1)

        if !gradientDefs.isEmpty {
            out += "  <defs>\n"
            for (i, def) in gradientDefs.enumerated() {
                out += "    " + def.replacingOccurrences(of: "@ID@", with: gradientIDs[i]) + "\n"
            }
            out += "  </defs>\n"
        }
        out += body
        out += "</svg>\n"
        return out

        func stopText(_ stop: GradientStop) -> String {
            let c = stop.color
            let hex = String(
                format: "#%02x%02x%02x", c.count > 0 ? c[0] : 0, c.count > 1 ? c[1] : 0,
                c.count > 2 ? c[2] : 0)
            return "<stop offset=\"\(SVGNum.text(stop.offset))\" stop-color=\"\(hex)\"/>"
        }

        func shapeText(_ s: ShapeNode, gradientID: (PaintValue) -> String?) -> String {
            var attrs = ""
            attrs += nodeAttrText(s.attributes)

            switch s.kind {
            case .path(let paths):
                // Export bakes live corners — SVG has no per-vertex radius.
                let baked = paths.map { $0.flattenedCorners }
                attrs += " d=\"\(SVGPathData.serialize(baked, emitArcs: options.emitArcs))\""
            case .line(let a, let b):
                attrs +=
                    " x1=\"\(SVGNum.text(a.x))\" y1=\"\(SVGNum.text(a.y))\""
                    + " x2=\"\(SVGNum.text(b.x))\" y2=\"\(SVGNum.text(b.y))\""
            case .polyline(let pts), .polygon(let pts):
                let text = pts.map { "\(SVGNum.text($0.x)),\(SVGNum.text($0.y))" }
                    .joined(separator: " ")
                attrs += " points=\"\(text)\""
            case .rect(let x, let y, let w, let h, let rx, let ry):
                attrs +=
                    " x=\"\(SVGNum.text(x))\" y=\"\(SVGNum.text(y))\""
                    + " width=\"\(SVGNum.text(w))\" height=\"\(SVGNum.text(h))\""
                if let rx { attrs += " rx=\"\(SVGNum.text(rx))\"" }
                if let ry { attrs += " ry=\"\(SVGNum.text(ry))\"" }
            case .circle(let c, let r):
                attrs +=
                    " cx=\"\(SVGNum.text(c.x))\" cy=\"\(SVGNum.text(c.y))\""
                    + " r=\"\(SVGNum.text(r))\""
            case .ellipse(let c, let rx, let ry):
                attrs +=
                    " cx=\"\(SVGNum.text(c.x))\" cy=\"\(SVGNum.text(c.y))\""
                    + " rx=\"\(SVGNum.text(rx))\" ry=\"\(SVGNum.text(ry))\""
            }

            if let t = s.transform, !t.raw.isEmpty {
                attrs += " transform=\"\(escapeAttr(t.raw))\""
            }

            // Gradient fills/strokes are indirected through defs references.
            var style = s.style
            if let fill = style.fill, let id = gradientID(fill) {
                style.fill = .reference(id)
            }
            if let stroke = style.stroke, let id = gradientID(stroke) {
                style.stroke = .reference(id)
            }
            if !style.declarations.isEmpty {
                attrs += " style=\"\(escapeAttr(SVGStyle.serialize(style)))\""
            }

            let tag: String
            switch s.kind {
            case .path: tag = "path"
            case .line: tag = "line"
            case .polyline: tag = "polyline"
            case .polygon: tag = "polygon"
            case .rect: tag = "rect"
            case .circle: tag = "circle"
            case .ellipse: tag = "ellipse"
            }
            return "<\(tag)\(attrs)/>"
        }
    }

    static func nodeAttrText(_ attributes: NodeAttributes) -> String {
        var out = ""
        if let id = attributes.svgID {
            out += " id=\"\(escapeAttr(id))\""
        }
        for attr in attributes.extras {
            out += " \(attr.name)=\"\(escapeAttr(attr.value))\""
        }
        return out
    }

    static func escapeAttr(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}
