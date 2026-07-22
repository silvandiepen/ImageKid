import Foundation

/// Per-icon metadata in the open-icon layout: a sibling `meta/` directory
/// next to the scanned icons folder holds one flat JSON file per icon named
/// `<svgFileName>.json` (e.g. `icon_add-fat.svg.json` for `icon_add-fat.svg`,
/// regardless of the icon's category subfolder).
///
/// The real corpus is uniform — every file carries `title`, `description`,
/// `category: [String]` and `tag: [String]` — but decoding tolerates missing
/// keys (all optional / defaulted) and accepts a bare string where a list is
/// expected, so partially written metadata never fails a scan.
public struct IconMeta: Codable, Equatable, Sendable {
    /// Human-readable display title (e.g. "Add Fat").
    public var title: String?
    /// Long-form description of the icon.
    public var description: String?
    /// Metadata categories (display taxonomy, e.g. ["Interface"]); this is
    /// independent of the folder-based `IconEntry.category`.
    public var category: [String]
    /// Search keywords / tags.
    public var tag: [String]

    public init(
        title: String? = nil, description: String? = nil,
        category: [String] = [], tag: [String] = []
    ) {
        self.title = title
        self.description = description
        self.category = category
        self.tag = tag
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, category, tag
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        category = try Self.stringList(c, .category)
        tag = try Self.stringList(c, .tag)
    }

    /// Decodes `[String]`, tolerating a bare `String` (wrapped) or a missing
    /// key (empty list).
    private static func stringList(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) throws -> [String] {
        guard c.contains(key) else { return [] }
        if let list = try? c.decode([String].self, forKey: key) { return list }
        if let single = try? c.decode(String.self, forKey: key) { return [single] }
        return []
    }

    /// Every searchable text field, used by `Workspace.search`.
    var searchTerms: [String] {
        var terms = tag + category
        if let title { terms.append(title) }
        return terms
    }
}
