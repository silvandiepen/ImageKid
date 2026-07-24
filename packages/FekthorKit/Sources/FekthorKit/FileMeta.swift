import Foundation

/// Per-file editor metadata carried INSIDE the SVG, so swatches and named
/// styles work on a single detached file (no workspace, no sidecar): one
/// `<metadata id="fekthor-meta">{json}</metadata>` element. `<metadata>` is
/// valid SVG that renderers ignore, and the reader's RawNode passthrough
/// preserves it verbatim — the block round-trips through open/save without
/// any special casing. Exports MUST NOT ship it: `ExportRunner.apply` (and
/// anything else producing deliverables) strips it via `removing`.
public enum FileMeta {
    /// The element id marking the block (and the RawNode carrying it).
    public static let elementID = "fekthor-meta"

    /// The payload: file-local swatches (hex strings, `#rrggbb`) and named
    /// styles (same shape as workspace styles). Both optional so the JSON
    /// stays minimal; encodes deterministically (sorted keys).
    public struct Meta: Codable, Equatable, Sendable {
        public var swatches: [String]?
        public var styles: [NamedStyle]?
        /// Resolved copies of the animation defs this icon uses (master
        /// lives in the workfile) — the SVG stays self-contained.
        public var animations: [AnimationDef]?
        /// The icon's animation scene: its ordered bindings.
        public var animationBindings: [AnimationBinding]?
        /// Per-icon toggle; nil falls through to the workspace setting.
        public var animationsEnabled: Bool?
        /// Per-icon overrides of the workspace animation defaults.
        public var animationSettings: AnimationSettings?
        public init(
            swatches: [String]? = nil, styles: [NamedStyle]? = nil,
            animations: [AnimationDef]? = nil,
            animationBindings: [AnimationBinding]? = nil,
            animationsEnabled: Bool? = nil,
            animationSettings: AnimationSettings? = nil
        ) {
            self.swatches = swatches
            self.styles = styles
            self.animations = animations
            self.animationBindings = animationBindings
            self.animationsEnabled = animationsEnabled
            self.animationSettings = animationSettings
        }

        public var isEmpty: Bool {
            (swatches?.isEmpty ?? true) && (styles?.isEmpty ?? true)
                && (animations?.isEmpty ?? true) && (animationBindings?.isEmpty ?? true)
                && animationsEnabled == nil && animationSettings == nil
        }
    }

    // MARK: - Read

    /// The document's metadata block, decoded; nil when absent or unreadable.
    public static func read(from doc: GraphicDocument) -> Meta? {
        for node in doc.nodes {
            guard case .raw(let raw) = node, isMetaXML(raw.xml) else { continue }
            guard let json = payload(of: raw.xml),
                let meta = try? JSONDecoder().decode(Meta.self, from: Data(json.utf8))
            else { return nil }
            return meta
        }
        return nil
    }

    // MARK: - Write

    /// The document with its metadata block replaced by `meta` (inserted at
    /// the end when absent). An empty meta removes the block entirely, so
    /// untouched files never grow one.
    public static func writing(_ meta: Meta, to doc: GraphicDocument) -> GraphicDocument {
        guard !meta.isEmpty else { return removing(from: doc) }
        var normalized = meta
        if normalized.swatches?.isEmpty == true { normalized.swatches = nil }
        if normalized.styles?.isEmpty == true { normalized.styles = nil }
        if normalized.animations?.isEmpty == true { normalized.animations = nil }
        if normalized.animationBindings?.isEmpty == true { normalized.animationBindings = nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(normalized) else { return doc }
        let json = String(decoding: data, as: UTF8.self)
        let xml = "<metadata id=\"\(elementID)\">\(escapeText(json))</metadata>"
        var out = doc
        for i in out.nodes.indices {
            guard case .raw(let raw) = out.nodes[i], isMetaXML(raw.xml) else { continue }
            out.nodes[i] = .raw(RawNode(id: raw.id, xml: xml))
            return out
        }
        out.nodes.append(.raw(RawNode(id: out.nextNodeID, xml: xml)))
        return out
    }

    /// The document without its metadata block (export stripping).
    public static func removing(from doc: GraphicDocument) -> GraphicDocument {
        var out = doc
        out.nodes.removeAll {
            if case .raw(let raw) = $0 { return isMetaXML(raw.xml) }
            return false
        }
        return out
    }

    // MARK: - Internals

    /// Is this raw fragment the fekthor metadata element? Matches the tag
    /// and the id attribute without a full parse (the fragment is our own
    /// canonical serialization, or the reader's canonicalized passthrough).
    static func isMetaXML(_ xml: String) -> Bool {
        guard xml.hasPrefix("<metadata") else { return false }
        guard let close = xml.firstIndex(of: ">") else { return false }
        return xml[..<close].contains("id=\"\(elementID)\"")
    }

    /// The unescaped text content between the metadata tags.
    static func payload(of xml: String) -> String? {
        guard let open = xml.firstIndex(of: ">"),
            let closeTag = xml.range(of: "</metadata>", options: .backwards)
        else { return nil }
        let inner = String(xml[xml.index(after: open)..<closeTag.lowerBound])
        return unescapeText(inner)
    }

    /// Text-node escaping, mirroring the reader's passthrough serialization.
    static func escapeText(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }

    static func unescapeText(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
