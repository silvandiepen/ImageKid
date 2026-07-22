import Foundation

/// The `.fekthor` workfile: Codable JSON holding everything that does NOT
/// belong inside clean SVGs — workspace folder reference, categories,
/// artboard metadata, export profiles, style tokens, container slots — and
/// optionally EMBEDDED artboards (geometry as SVG text: one serialization
/// path, one fidelity guarantee) for self-contained documents.
///
/// v1 ships the schema and single-document embedding; the workspace fields
/// are forward-compatible stubs consumed by P1–P3. Decoding tolerates
/// unknown keys (Codable default); encoding is deterministic
/// (.sortedKeys + .prettyPrinted → diffable files).
public struct Workfile: Codable, Equatable, Sendable {
    public var version: Int
    /// Workspace folder (P1): path is stored relative to the workfile when
    /// possible; the security-scoped bookmark restores sandbox access.
    public var folder: FolderRef?
    /// Self-contained artboards, geometry embedded as SVG text.
    public var artboards: [EmbeddedArtboard]?
    public var categories: [String]?
    public var exportProfiles: [ExportProfile]?
    public var styleTokens: [StyleToken]?
    public var containers: [ContainerSlot]?
    /// Container memberships (P2): icon name → names of containers the icon
    /// is exported into (see `Containers.matrixExports`).
    public var containerMemberships: [String: [String]]?

    public init(
        version: Int = 1, folder: FolderRef? = nil, artboards: [EmbeddedArtboard]? = nil,
        categories: [String]? = nil, exportProfiles: [ExportProfile]? = nil,
        styleTokens: [StyleToken]? = nil, containers: [ContainerSlot]? = nil,
        containerMemberships: [String: [String]]? = nil
    ) {
        self.version = version
        self.folder = folder
        self.artboards = artboards
        self.categories = categories
        self.exportProfiles = exportProfiles
        self.styleTokens = styleTokens
        self.containers = containers
        self.containerMemberships = containerMemberships
    }

    public struct FolderRef: Codable, Equatable, Sendable {
        public var path: String
        public var bookmark: Data?
        public init(path: String, bookmark: Data? = nil) {
            self.path = path
            self.bookmark = bookmark
        }
    }

    public struct EmbeddedArtboard: Codable, Equatable, Sendable {
        public var name: String
        public var svg: String
        public init(name: String, svg: String) {
            self.name = name
            self.svg = svg
        }
    }

    /// P2 stub: a named export pipeline. Actions grow as typed values later;
    /// v1 keeps them as opaque strings so old builds skip what they don't know.
    public struct ExportProfile: Codable, Equatable, Sendable {
        public var name: String
        public var actions: [String]?
        public var output: String?
        public init(name: String, actions: [String]? = nil, output: String? = nil) {
            self.name = name
            self.actions = actions
            self.output = output
        }
    }

    /// P3 stub: a colour-slot token (outline = #010101, …).
    public struct StyleToken: Codable, Equatable, Sendable {
        public var name: String
        public var value: String
        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    /// P2 stub: a container's content slot (position + fit rule).
    public struct ContainerSlot: Codable, Equatable, Sendable {
        public var container: String
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var fit: String?
        public init(
            container: String, x: Double, y: Double, width: Double, height: Double,
            fit: String? = nil
        ) {
            self.container = container
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.fit = fit
        }
    }

    // MARK: I/O

    public static func decode(_ data: Data) throws -> Workfile {
        try JSONDecoder().decode(Workfile.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }
}
