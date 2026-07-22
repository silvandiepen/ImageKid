import Foundation

/// SVG reader for the icon subset (docs/fekthor/EDITOR-PLAN.md): built on
/// Foundation's SAX `XMLParser`. Shapes and groups become typed nodes;
/// `defs`/`style`/`clipPath`/unknown elements pass through as `RawNode`s
/// rebuilt from their events. `<style>` blocks with simple `.class { … }`
/// rules are additionally resolved into render-only class styles.
///
/// `XMLParser` loses attribute order; the writer's canonical attribute order
/// makes output deterministic regardless (idempotence-after-first-save is
/// the contract, not byte parity with arbitrary sources).
public enum SVGReader {
    public enum ReadError: Error {
        case notSVG
        case xml(String)
    }

    public static func read(_ text: String) throws -> GraphicDocument {
        try read(Data(text.utf8), sourceText: text)
    }

    public static func read(_ data: Data, sourceText: String? = nil) throws -> GraphicDocument {
        let text = sourceText ?? String(decoding: data, as: UTF8.self)
        let delegate = Collector()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() || delegate.finishedRoot else {
            let message = parser.parserError?.localizedDescription ?? "unknown parser error"
            throw ReadError.xml(message)
        }
        guard delegate.sawSVG else { throw ReadError.notSVG }

        var doc = GraphicDocument(
            viewBox: delegate.viewBox ?? ViewBox(width: 100, height: 100),
            rootAttributes: delegate.rootAttributes,
            hadXMLDeclaration: text.hasPrefix("<?xml"),
            nodes: delegate.rootChildren)

        // Resolve simple `.class { … }` rules into render-only class styles.
        if !delegate.cssRules.isEmpty {
            func resolve(_ nodes: inout [GraphicNode]) {
                for i in nodes.indices {
                    switch nodes[i] {
                    case .shape(var s):
                        if let cls = s.attributes.extras.first(where: { $0.name == "class" }) {
                            var merged = Style()
                            for name in cls.value.split(separator: " ") {
                                if let rule = delegate.cssRules[String(name)] {
                                    for d in rule.declarations { merged.set(d.name, d.value) }
                                }
                            }
                            if !merged.declarations.isEmpty { s.classStyle = merged }
                            nodes[i] = .shape(s)
                        }
                    case .group(var g):
                        resolve(&g.children)
                        nodes[i] = .group(g)
                    default:
                        break
                    }
                }
            }
            resolve(&doc.nodes)
        }
        return doc
    }

    // MARK: - Transform parsing

    /// Parse an SVG transform list into a single matrix (a b c d tx ty).
    public static func parseTransform(_ raw: String) -> TransformValue? {
        var matrix: [Double] = [1, 0, 0, 1, 0, 0]
        func multiply(_ m: [Double]) {
            let a = matrix
            matrix = [
                a[0] * m[0] + a[2] * m[1],
                a[1] * m[0] + a[3] * m[1],
                a[0] * m[2] + a[2] * m[3],
                a[1] * m[2] + a[3] * m[3],
                a[0] * m[4] + a[2] * m[5] + a[4],
                a[1] * m[4] + a[3] * m[5] + a[5],
            ]
        }
        var found = false
        var scanner = raw[...]
        while let open = scanner.firstIndex(of: "(") {
            let name = scanner[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                .trimmingCharacters(in: .whitespaces)
            guard let close = scanner[open...].firstIndex(of: ")") else { break }
            let argsText = scanner[scanner.index(after: open)..<close]
            let args = argsText.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
                .compactMap { Double($0) }
            switch name {
            case "translate":
                let tx = args.count > 0 ? args[0] : 0
                let ty = args.count > 1 ? args[1] : 0
                multiply([1, 0, 0, 1, tx, ty])
                found = true
            case "scale":
                let sx = args.count > 0 ? args[0] : 1
                let sy = args.count > 1 ? args[1] : sx
                multiply([sx, 0, 0, sy, 0, 0])
                found = true
            case "rotate":
                let a = (args.count > 0 ? args[0] : 0) * .pi / 180
                if args.count >= 3 {
                    multiply([1, 0, 0, 1, args[1], args[2]])
                    multiply([cos(a), sin(a), -sin(a), cos(a), 0, 0])
                    multiply([1, 0, 0, 1, -args[1], -args[2]])
                } else {
                    multiply([cos(a), sin(a), -sin(a), cos(a), 0, 0])
                }
                found = true
            case "matrix":
                if args.count >= 6 {
                    multiply(Array(args[0..<6]))
                    found = true
                }
            case "skewX":
                if args.count > 0 {
                    multiply([1, 0, tan(args[0] * .pi / 180), 1, 0, 0])
                    found = true
                }
            case "skewY":
                if args.count > 0 {
                    multiply([1, tan(args[0] * .pi / 180), 0, 1, 0, 0])
                    found = true
                }
            default:
                break
            }
            scanner = scanner[scanner.index(after: close)...]
        }
        guard found else { return nil }
        return TransformValue(raw: raw, matrix: matrix)
    }

    // MARK: - Points parsing (polyline/polygon)

    static func parsePoints(_ text: String) -> [Pt] {
        let numbers = text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" })
            .compactMap { Double($0) }
        var out: [Pt] = []
        var i = 0
        while i + 1 < numbers.count {
            out.append(Pt(numbers[i], numbers[i + 1]))
            i += 2
        }
        return out
    }

    // MARK: - SAX collector

    final class Collector: NSObject, XMLParserDelegate {
        var sawSVG = false
        var finishedRoot = false
        var viewBox: ViewBox?
        var rootAttributes: [XMLAttr] = []
        var rootChildren: [GraphicNode] = []
        var cssRules: [String: Style] = [:]

        private var nextID = 0
        private var groupStack: [GroupNode] = []
        /// When non-zero we are inside a raw (passthrough) element and only
        /// collect serialized XML.
        private var rawDepth = 0
        private var rawBuffer = ""
        private var rawIsStyle = false
        private var styleText = ""

        private static let shapeTags: Set<String> = [
            "path", "line", "polyline", "polygon", "rect", "circle", "ellipse",
        ]

        private func takeID() -> Int {
            defer { nextID += 1 }
            return nextID
        }

        private func append(_ node: GraphicNode) {
            if groupStack.isEmpty {
                rootChildren.append(node)
            } else {
                groupStack[groupStack.count - 1].children.append(node)
            }
        }

        /// Canonical, deterministic attribute capture: known geometry slots
        /// are consumed by the caller; this collects id + the remaining
        /// attributes in a fixed order (class, data-name, then sorted).
        private func nodeAttributes(
            _ attrs: [String: String], consumed: Set<String>
        ) -> NodeAttributes {
            var out = NodeAttributes()
            out.svgID = attrs["id"]
            var extras: [XMLAttr] = []
            if let cls = attrs["class"] { extras.append(XMLAttr(name: "class", value: cls)) }
            if let dn = attrs["data-name"] { extras.append(XMLAttr(name: "data-name", value: dn)) }
            let known = consumed.union(["id", "class", "data-name", "style", "transform"])
            for key in attrs.keys.sorted() where !known.contains(key) {
                extras.append(XMLAttr(name: key, value: attrs[key]!))
            }
            out.extras = extras
            return out
        }

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
            qualifiedName: String?, attributes attrs: [String: String] = [:]
        ) {
            if rawDepth > 0 {
                rawBuffer += rawOpenTag(name, attrs)
                rawDepth += 1
                return
            }
            switch name {
            case "svg":
                sawSVG = true
                if let vb = attrs["viewBox"] {
                    let n = vb.split(separator: " ").compactMap { Double($0) }
                    if n.count == 4 {
                        viewBox = ViewBox(minX: n[0], minY: n[1], width: n[2], height: n[3])
                    }
                } else if let w = attrs["width"].flatMap(Double.init),
                    let h = attrs["height"].flatMap(Double.init)
                {
                    viewBox = ViewBox(width: w, height: h)
                }
                // Canonical root attribute order: id, xmlns, xmlns:xlink,
                // version, then the rest sorted (viewBox is typed separately).
                var out: [XMLAttr] = []
                for key in ["id", "xmlns", "xmlns:xlink", "version"] {
                    if let v = attrs[key] { out.append(XMLAttr(name: key, value: v)) }
                }
                let known: Set<String> = ["id", "xmlns", "xmlns:xlink", "version", "viewBox"]
                for key in attrs.keys.sorted() where !known.contains(key) {
                    out.append(XMLAttr(name: key, value: attrs[key]!))
                }
                rootAttributes = out
            case "g":
                var group = GroupNode(id: takeID())
                group.style = attrs["style"].map(SVGStyle.parse) ?? Style()
                group.transform = attrs["transform"].flatMap(SVGReader.parseTransform)
                group.attributes = nodeAttributes(attrs, consumed: [])
                groupStack.append(group)
            case _ where Collector.shapeTags.contains(name):
                if let node = shapeNode(name, attrs) {
                    append(.shape(node))
                }
            default:
                // Raw passthrough (defs, style, clipPath, title, unknown).
                rawDepth = 1
                rawIsStyle = name == "style"
                styleText = ""
                rawBuffer = rawOpenTag(name, attrs)
            }
        }

        func parser(
            _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
            qualifiedName: String?
        ) {
            if rawDepth > 0 {
                rawDepth -= 1
                rawBuffer += "</\(name)>"
                if rawDepth == 0 {
                    append(.raw(RawNode(id: takeID(), xml: rawBuffer)))
                    if rawIsStyle { parseCSS(styleText) }
                    rawBuffer = ""
                    rawIsStyle = false
                }
                return
            }
            switch name {
            case "g":
                if let group = groupStack.popLast() {
                    append(.group(group))
                }
            case "svg":
                finishedRoot = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if rawDepth > 0 {
                rawBuffer += escapeText(string)
                if rawIsStyle { styleText += string }
            }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if rawDepth > 0 {
                let text = String(decoding: CDATABlock, as: UTF8.self)
                rawBuffer += "<![CDATA[\(text)]]>"
                if rawIsStyle { styleText += text }
            }
        }

        // MARK: shapes

        private func shapeNode(_ name: String, _ attrs: [String: String]) -> ShapeNode? {
            func d(_ key: String) -> Double? { attrs[key].flatMap(Double.init) }
            let kind: ShapeKind
            var consumed: Set<String>
            switch name {
            case "path":
                guard let dAttr = attrs["d"],
                    let paths = try? SVGPathData.parse(dAttr)
                else { return nil }
                kind = .path(paths)
                consumed = ["d"]
            case "line":
                kind = .line(
                    Pt(d("x1") ?? 0, d("y1") ?? 0), Pt(d("x2") ?? 0, d("y2") ?? 0))
                consumed = ["x1", "y1", "x2", "y2"]
            case "polyline":
                kind = .polyline(SVGReader.parsePoints(attrs["points"] ?? ""))
                consumed = ["points"]
            case "polygon":
                kind = .polygon(SVGReader.parsePoints(attrs["points"] ?? ""))
                consumed = ["points"]
            case "rect":
                kind = .rect(
                    x: d("x") ?? 0, y: d("y") ?? 0, width: d("width") ?? 0,
                    height: d("height") ?? 0, rx: d("rx"), ry: d("ry"))
                consumed = ["x", "y", "width", "height", "rx", "ry"]
            case "circle":
                kind = .circle(center: Pt(d("cx") ?? 0, d("cy") ?? 0), r: d("r") ?? 0)
                consumed = ["cx", "cy", "r"]
            case "ellipse":
                kind = .ellipse(
                    center: Pt(d("cx") ?? 0, d("cy") ?? 0), rx: d("rx") ?? 0, ry: d("ry") ?? 0)
                consumed = ["cx", "cy", "rx", "ry"]
            default:
                return nil
            }
            return ShapeNode(
                id: takeID(), kind: kind,
                style: attrs["style"].map(SVGStyle.parse) ?? Style(),
                attributes: nodeAttributes(attrs, consumed: consumed),
                transform: attrs["transform"].flatMap(SVGReader.parseTransform))
        }

        // MARK: raw serialization helpers

        private func rawOpenTag(_ name: String, _ attrs: [String: String]) -> String {
            var out = "<\(name)"
            for key in canonicalRawAttrOrder(attrs) {
                out += " \(key)=\"\(escapeAttr(attrs[key]!))\""
            }
            out += ">"
            return out
        }

        private func canonicalRawAttrOrder(_ attrs: [String: String]) -> [String] {
            var keys: [String] = []
            for k in ["id", "class"] where attrs[k] != nil { keys.append(k) }
            for k in attrs.keys.sorted() where !keys.contains(k) { keys.append(k) }
            return keys
        }

        private func escapeAttr(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
        }

        private func escapeText(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
        }

        // MARK: minimal CSS (.class { decls })

        private func parseCSS(_ text: String) {
            var scanner = text[...]
            while let dot = scanner.firstIndex(of: ".") {
                guard let open = scanner[dot...].firstIndex(of: "{"),
                    let close = scanner[open...].firstIndex(of: "}")
                else { break }
                let names = scanner[scanner.index(after: dot)..<open]
                let body = scanner[scanner.index(after: open)..<close]
                let style = SVGStyle.parse(String(body))
                for sel in names.split(separator: ",") {
                    let cls = sel.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    if !cls.isEmpty { cssRules[cls] = style }
                }
                scanner = scanner[scanner.index(after: close)...]
            }
        }
    }
}
