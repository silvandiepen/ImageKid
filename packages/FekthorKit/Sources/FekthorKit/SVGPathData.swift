import Foundation

// MARK: - SVG number formatting (shared by parsers, writer and tests)

public enum SVGNum {
    /// Corpus-style number text: up to 2 decimals, trailing zeros trimmed,
    /// leading zero dropped (`.5`), `-0` normalized to `0`. Locale-safe.
    public static func text(_ v: Double) -> String {
        var r = (v * 100).rounded() / 100
        if r == 0 { r = 0 }  // avoid "-0"
        if r == r.rounded() {
            return String(Int(r))
        }
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        if s.hasPrefix("0.") { s.removeFirst() }
        if s.hasPrefix("-0.") { s = "-" + s.dropFirst(2) }
        return s
    }
}

// MARK: - Path data ("d" attribute)

/// Full SVG path-data grammar → typed subpaths, and back.
/// Parser accepts every command (MmLlHhVvCcSsQqTtAaZz), implicit command
/// repetition, compact numbers (`.5`, `-3-4`, `.55.45`, `5e-2`) and
/// comma/whitespace separation. Arcs become `.arc` when circular, cubic
/// approximations otherwise.
public enum SVGPathData {
    public enum ParseError: Error, Equatable {
        case unexpectedCharacter(Character)
        case truncatedArguments(command: Character)
        case noCommands
    }

    // MARK: Parse

    public static func parse(_ d: String) throws -> [RefinedPath] {
        var scanner = NumberScanner(text: d)
        var paths: [RefinedPath] = []

        var current = Pt(0, 0)
        var subpathStart = Pt(0, 0)
        var start: Pt? = nil
        var segments: [RefinedSegment] = []
        var closed = false
        var prevCubicControl: Pt? = nil  // for S reflection
        var prevQuadControl: Pt? = nil  // for T reflection
        var sawCommand = false

        func flush() {
            if let s = start, !(segments.isEmpty && !closed) {
                paths.append(RefinedPath(start: s, segments: segments, closed: closed))
            } else if let s = start, closed {
                paths.append(RefinedPath(start: s, segments: segments, closed: true))
            }
            start = nil
            segments = []
            closed = false
        }

        func begin(at p: Pt) {
            flush()
            start = p
            subpathStart = p
            current = p
        }

        var command: Character? = nil
        while let token = scanner.nextToken() {
            switch token {
            case .command(let c):
                command = c
                sawCommand = true
                if c == "Z" || c == "z" {
                    closed = true
                    current = subpathStart
                    flush()
                    // Per spec: a command after Z starts a new subpath at the
                    // same initial point.
                    start = nil
                    command = nil
                    continue
                }
            case .number(let first):
                // Implicit repetition: a number where a command is expected
                // repeats the previous command (M→L, m→l after the first pair).
                guard let c = command else { throw ParseError.noCommands }
                scanner.pushBack(first)
                _ = c  // handled below by falling through with same command
            }
            guard var c = command else { continue }

            // After the first M/m pair, further pairs are treated as L/l.
            func relative() -> Bool { c.isLowercase }
            func take(_ n: Int) throws -> [Double] {
                var out: [Double] = []
                for _ in 0..<n {
                    guard let v = scanner.nextNumber() else {
                        throw ParseError.truncatedArguments(command: c)
                    }
                    out.append(v)
                }
                return out
            }
            func pt(_ x: Double, _ y: Double) -> Pt {
                relative() ? Pt(current.x + x, current.y + y) : Pt(x, y)
            }

            switch c {
            case "M", "m":
                let a = try take(2)
                begin(at: pt(a[0], a[1]))
                prevCubicControl = nil
                prevQuadControl = nil
                // Subsequent pairs are implicit LineTos.
                c = relative() ? "l" : "L"
                command = c
                while scanner.peekIsNumber() {
                    let b = try take(2)
                    if start == nil { start = current }
                    let p = pt(b[0], b[1])
                    segments.append(.line(to: p))
                    current = p
                }
            case "L", "l":
                if start == nil { begin(at: current) }
                repeat {
                    let a = try take(2)
                    let p = pt(a[0], a[1])
                    segments.append(.line(to: p))
                    current = p
                } while scanner.peekIsNumber()
                prevCubicControl = nil
                prevQuadControl = nil
            case "H", "h":
                if start == nil { begin(at: current) }
                repeat {
                    let a = try take(1)
                    let p = relative() ? Pt(current.x + a[0], current.y) : Pt(a[0], current.y)
                    segments.append(.line(to: p))
                    current = p
                } while scanner.peekIsNumber()
                prevCubicControl = nil
                prevQuadControl = nil
            case "V", "v":
                if start == nil { begin(at: current) }
                repeat {
                    let a = try take(1)
                    let p = relative() ? Pt(current.x, current.y + a[0]) : Pt(current.x, a[0])
                    segments.append(.line(to: p))
                    current = p
                } while scanner.peekIsNumber()
                prevCubicControl = nil
                prevQuadControl = nil
            case "C", "c":
                if start == nil { begin(at: current) }
                repeat {
                    let a = try take(6)
                    let c1 = pt(a[0], a[1])
                    let c2 = pt(a[2], a[3])
                    let p = pt(a[4], a[5])
                    segments.append(.cubic(c1: c1, c2: c2, to: p))
                    prevCubicControl = c2
                    current = p
                } while scanner.peekIsNumber()
                prevQuadControl = nil
            case "S", "s":
                if start == nil { begin(at: current) }
                repeat {
                    let a = try take(4)
                    let c1: Pt
                    if let pc = prevCubicControl {
                        c1 = Pt(2 * current.x - pc.x, 2 * current.y - pc.y)
                    } else {
                        c1 = current
                    }
                    let c2 = pt(a[0], a[1])
                    let p = pt(a[2], a[3])
                    segments.append(.cubic(c1: c1, c2: c2, to: p))
                    prevCubicControl = c2
                    current = p
                } while scanner.peekIsNumber()
                prevQuadControl = nil
            case "Q", "q":
                if start == nil { begin(at: current) }
                repeat {
                    let a = try take(4)
                    let q = pt(a[0], a[1])
                    let p = pt(a[2], a[3])
                    segments.append(elevated(from: current, q: q, to: p))
                    prevQuadControl = q
                    current = p
                } while scanner.peekIsNumber()
                prevCubicControl = nil
            case "T", "t":
                if start == nil { begin(at: current) }
                repeat {
                    let a = try take(2)
                    let q: Pt
                    if let pq = prevQuadControl {
                        q = Pt(2 * current.x - pq.x, 2 * current.y - pq.y)
                    } else {
                        q = current
                    }
                    let p = pt(a[0], a[1])
                    segments.append(elevated(from: current, q: q, to: p))
                    prevQuadControl = q
                    current = p
                } while scanner.peekIsNumber()
                prevCubicControl = nil
            case "A", "a":
                if start == nil { begin(at: current) }
                repeat {
                    let a = try take(7)
                    let p = pt(a[5], a[6])
                    segments.append(
                        contentsOf: arcSegments(
                            from: current, rx: a[0], ry: a[1], xRotDeg: a[2],
                            largeArc: a[3] != 0, sweep: a[4] != 0, to: p))
                    current = p
                } while scanner.peekIsNumber()
                prevCubicControl = nil
                prevQuadControl = nil
            default:
                throw ParseError.unexpectedCharacter(c)
            }
        }
        guard sawCommand else { throw ParseError.noCommands }
        flush()
        return paths
    }

    /// Quadratic → cubic degree elevation.
    static func elevated(from p0: Pt, q: Pt, to p3: Pt) -> RefinedSegment {
        let c1 = Pt(p0.x + 2.0 / 3.0 * (q.x - p0.x), p0.y + 2.0 / 3.0 * (q.y - p0.y))
        let c2 = Pt(p3.x + 2.0 / 3.0 * (q.x - p3.x), p3.y + 2.0 / 3.0 * (q.y - p3.y))
        return .cubic(c1: c1, c2: c2, to: p3)
    }

    /// Endpoint→centre conversion (SVG spec F.6.5); circular arcs become
    /// `.arc`, elliptical ones become ≤90° cubic spans.
    static func arcSegments(
        from p0: Pt, rx rxIn: Double, ry ryIn: Double, xRotDeg: Double, largeArc: Bool,
        sweep: Bool, to p1: Pt
    ) -> [RefinedSegment] {
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if rx < 1e-9 || ry < 1e-9 || (p0.x == p1.x && p0.y == p1.y) {
            return [.line(to: p1)]
        }
        let phi = xRotDeg * .pi / 180
        let cosP = cos(phi)
        let sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2
        let dy = (p0.y - p1.y) / 2
        let x1p = cosP * dx + sinP * dy
        let y1p = -sinP * dx + cosP * dy
        // Correct out-of-range radii.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = lambda.squareRoot()
            rx *= s
            ry *= s
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = (max(0, num) / max(1e-12, den)).squareRoot()
        if largeArc == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = ((ux * ux + uy * uy) * (vx * vx + vy * vy)).squareRoot()
            var a = acos(min(1, max(-1, dot / max(1e-12, len))))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle(
            (x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        // Circular, unrotated in effect: emit a true arc segment.
        if abs(rx - ry) < 1e-9 {
            let sa = theta1 + phi
            let ea = theta1 + delta + phi
            return [
                .arc(
                    center: Pt(cx, cy), radius: rx, startAngle: sa, endAngle: ea,
                    clockwise: delta > 0)
            ]
        }

        // Elliptical: cubic approximation in ≤90° spans.
        var out: [RefinedSegment] = []
        let chunks = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / Double(chunks)
        var t = theta1
        for _ in 0..<chunks {
            let t2 = t + step
            let k = 4.0 / 3.0 * tan(step / 4)
            func point(_ a: Double) -> Pt {
                Pt(
                    cx + rx * cos(a) * cosP - ry * sin(a) * sinP,
                    cy + rx * cos(a) * sinP + ry * sin(a) * cosP)
            }
            func deriv(_ a: Double) -> Pt {
                Pt(
                    -rx * sin(a) * cosP - ry * cos(a) * sinP,
                    -rx * sin(a) * sinP + ry * cos(a) * cosP)
            }
            let s = point(t)
            let e = point(t2)
            let ds = deriv(t)
            let de = deriv(t2)
            out.append(
                .cubic(
                    c1: Pt(s.x + k * ds.x, s.y + k * ds.y),
                    c2: Pt(e.x - k * de.x, e.y - k * de.y), to: e))
            t = t2
        }
        return out
    }

    // MARK: Serialize

    /// Path → `d` text. Emits absolute commands (M/L/C/Z) in corpus number
    /// style; arcs are converted to cubics by the caller when needed.
    public static func serialize(_ paths: [RefinedPath], emitArcs: Bool) -> String {
        var parts: [String] = []
        for rp in paths {
            var d = "M\(SVGNum.text(rp.start.x)),\(SVGNum.text(rp.start.y))"
            let source = emitArcs ? rp : Editing.cubicized(rp)
            for seg in source.segments {
                switch seg {
                case .line(let to):
                    d += "L\(SVGNum.text(to.x)),\(SVGNum.text(to.y))"
                case .cubic(let c1, let c2, let to):
                    d +=
                        "C\(SVGNum.text(c1.x)),\(SVGNum.text(c1.y)),"
                        + "\(SVGNum.text(c2.x)),\(SVGNum.text(c2.y)),"
                        + "\(SVGNum.text(to.x)),\(SVGNum.text(to.y))"
                case .arc(let c, let r, let sa, let ea, let cw):
                    // SVG arc from typed arc: endpoint form.
                    let end = Pt(c.x + r * cos(ea), c.y + r * sin(ea))
                    var sweepAngle = cw ? ea - sa : sa - ea
                    while sweepAngle < 0 { sweepAngle += 2 * .pi }
                    while sweepAngle >= 2 * .pi { sweepAngle -= 2 * .pi }
                    let large = sweepAngle > .pi ? 1 : 0
                    let sweepFlag = cw ? 1 : 0
                    d +=
                        "A\(SVGNum.text(r)),\(SVGNum.text(r)),0,\(large),\(sweepFlag),"
                        + "\(SVGNum.text(end.x)),\(SVGNum.text(end.y))"
                }
            }
            if source.closed { d += "Z" }
            parts.append(d)
        }
        return parts.joined()
    }

    // MARK: Tokenizer

    enum Token {
        case command(Character)
        case number(Double)
    }

    struct NumberScanner {
        let scalars: [UInt8]
        var i = 0
        var pushed: Double? = nil

        init(text: String) {
            scalars = Array(text.utf8)
        }

        mutating func pushBack(_ v: Double) { pushed = v }

        mutating func skipSeparators() {
            while i < scalars.count {
                let c = scalars[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2C {
                    i += 1
                } else {
                    break
                }
            }
        }

        mutating func peekIsNumber() -> Bool {
            if pushed != nil { return true }
            skipSeparators()
            guard i < scalars.count else { return false }
            let c = scalars[i]
            return (c >= 0x30 && c <= 0x39) || c == 0x2E || c == 0x2D || c == 0x2B
        }

        mutating func nextNumber() -> Double? {
            if let p = pushed {
                pushed = nil
                return p
            }
            skipSeparators()
            guard i < scalars.count else { return nil }
            var j = i
            var sawDigit = false
            var sawDot = false
            var sawExp = false
            if scalars[j] == 0x2D || scalars[j] == 0x2B { j += 1 }
            loop: while j < scalars.count {
                let c = scalars[j]
                switch c {
                case 0x30...0x39:
                    sawDigit = true
                    j += 1
                case 0x2E:
                    if sawDot || sawExp { break loop }
                    sawDot = true
                    j += 1
                case 0x65, 0x45:  // e E
                    if sawExp || !sawDigit { break loop }
                    sawExp = true
                    j += 1
                    if j < scalars.count, scalars[j] == 0x2D || scalars[j] == 0x2B { j += 1 }
                case 0x2D, 0x2B:
                    break loop
                default:
                    break loop
                }
            }
            guard sawDigit else { return nil }
            let text = String(decoding: scalars[i..<j], as: UTF8.self)
            i = j
            return Double(text)
        }

        mutating func nextToken() -> Token? {
            if let p = pushed {
                pushed = nil
                return .number(p)
            }
            skipSeparators()
            guard i < scalars.count else { return nil }
            let c = scalars[i]
            let ch = Character(UnicodeScalar(c))
            if ch.isLetter {
                i += 1
                return .command(ch)
            }
            if let n = nextNumber() { return .number(n) }
            // Unparseable character: skip to avoid infinite loops.
            i += 1
            return nextToken()
        }
    }
}

// MARK: - Inline style parsing/serialization

public enum SVGStyle {
    static let numericProps: Set<String> = [
        "stroke-width", "opacity", "fill-opacity", "stroke-opacity",
        "stroke-miterlimit", "stroke-dashoffset",
    ]
    static let keywordProps: Set<String> = [
        "stroke-linecap", "stroke-linejoin", "fill-rule", "clip-rule",
    ]

    public static func parse(_ text: String) -> Style {
        var declarations: [StyleDeclaration] = []
        for part in text.split(separator: ";") {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let name = part[..<colon].trimmingCharacters(in: .whitespaces)
            let valueText = part[part.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !valueText.isEmpty else { continue }
            declarations.append(StyleDeclaration(name: name, value: value(name, valueText)))
        }
        return Style(declarations: declarations)
    }

    static func value(_ name: String, _ text: String) -> StyleValue {
        if name == "fill" || name == "stroke" {
            return .paint(paint(text))
        }
        if numericProps.contains(name) {
            // "4px" / ".5" / "10" — split a trailing unit.
            var digits = ""
            var unit = ""
            var inUnit = false
            for ch in text {
                if !inUnit, ch.isNumber || ch == "." || ch == "-" || ch == "+" || ch == "e" {
                    digits.append(ch)
                } else {
                    inUnit = true
                    unit.append(ch)
                }
            }
            if let n = Double(digits), unit.allSatisfy({ $0.isLetter || $0 == "%" }) {
                return .number(n, unit: unit.isEmpty ? nil : unit)
            }
            return .raw(text)
        }
        if keywordProps.contains(name) {
            return .keyword(text)
        }
        return .raw(text)
    }

    static func paint(_ text: String) -> PaintValue {
        if text == "none" { return PaintValue.none }
        if let c = PaintValue.parseHex(text) {
            return .color(r: c.r, g: c.g, b: c.b)
        }
        if text.hasPrefix("url(#"), text.hasSuffix(")") {
            return .reference(String(text.dropFirst(5).dropLast()))
        }
        return .raw(text)
    }

    /// Serialize with the corpus (Illustrator) convention: `name: value;`
    /// pairs joined with a space, trailing semicolon.
    public static func serialize(_ style: Style) -> String {
        style.declarations.map { "\($0.name): \(valueText($0.value));" }.joined(separator: " ")
    }

    public static func valueText(_ value: StyleValue) -> String {
        switch value {
        case .paint(let p): return paintText(p)
        case .number(let n, let unit): return SVGNum.text(n) + (unit ?? "")
        case .keyword(let k): return k
        case .raw(let r): return r
        }
    }

    static func paintText(_ p: PaintValue) -> String {
        switch p {
        case .none: return "none"
        case .color(let r, let g, let b):
            let full = String(format: "#%02x%02x%02x", r, g, b)
            // Shorthand when all three channels have doubled digits (#fff).
            let chars = Array(full.dropFirst())
            if chars[0] == chars[1], chars[2] == chars[3], chars[4] == chars[5] {
                return "#\(chars[0])\(chars[2])\(chars[4])"
            }
            return full
        case .reference(let id): return "url(#\(id))"
        case .linear, .radial:
            // Gradients are written via <defs> by the writer; a style-level
            // paint reference is produced there. This text form is only a
            // fallback and should not normally be hit.
            return "url(#gradient)"
        case .raw(let s): return s
        }
    }
}
