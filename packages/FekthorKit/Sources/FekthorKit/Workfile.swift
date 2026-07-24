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
    /// Workspace standards applied to new icons and the editor canvas:
    /// artboard size, grid, and drawing defaults. All optional so older
    /// workfiles decode unchanged.
    public var settings: WorkspaceSettings?
    public var exportProfiles: [ExportProfile]?
    public var styleTokens: [StyleToken]?
    /// Named graphic styles bound to nodes by SVG class (see `NamedStyles`).
    public var namedStyles: [NamedStyle]?
    /// Workspace colour swatches: hex colour strings shown in the picker.
    public var swatches: [String]?
    public var containers: [ContainerSlot]?
    /// Container memberships (P2): icon name → names of containers the icon
    /// is exported into (see `Containers.matrixExports`).
    public var containerMemberships: [String: [String]]?
    /// Role per entry NAME: "container" or "partial"; absent = plain icon.
    /// Only plain icons export by default — containers and partials are
    /// composition ingredients (see `EntryRole`).
    public var entryRoles: [String: String]?
    /// Partial name → container names it augments. At export a container is
    /// merged with its linked partials before content is composed in.
    public var partialLinks: [String: [String]]?

    public init(
        version: Int = 1, folder: FolderRef? = nil, artboards: [EmbeddedArtboard]? = nil,
        categories: [String]? = nil, settings: WorkspaceSettings? = nil,
        exportProfiles: [ExportProfile]? = nil,
        styleTokens: [StyleToken]? = nil, namedStyles: [NamedStyle]? = nil,
        swatches: [String]? = nil, containers: [ContainerSlot]? = nil,
        containerMemberships: [String: [String]]? = nil,
        entryRoles: [String: String]? = nil, partialLinks: [String: [String]]? = nil
    ) {
        self.version = version
        self.folder = folder
        self.artboards = artboards
        self.categories = categories
        self.settings = settings
        self.exportProfiles = exportProfiles
        self.styleTokens = styleTokens
        self.namedStyles = namedStyles
        self.swatches = swatches
        self.containers = containers
        self.containerMemberships = containerMemberships
        self.entryRoles = entryRoles
        self.partialLinks = partialLinks
    }

    /// The three kinds of workspace entry. Plain icons are the product;
    /// containers and partials exist to be merged into exports.
    public enum EntryRole: String, Equatable, Sendable {
        /// A real icon — exported by default, composable into containers.
        case icon
        /// A frame/backdrop with a content slot — never exported alone.
        case container
        /// A reusable fragment linked to containers — never exported alone.
        case partial
    }

    /// The role recorded for an entry name; unknown strings and absent
    /// entries are plain icons.
    public func role(of name: String) -> EntryRole {
        EntryRole(rawValue: entryRoles?[name] ?? "") ?? .icon
    }

    /// Whether a default (unscoped) export includes this entry: only plain
    /// icons do — containers and partials are ingredients.
    public func isExportedByDefault(_ name: String) -> Bool {
        role(of: name) == .icon
    }

    /// Workspace standards: the artboard size new icons start with, the
    /// editor grid, and drawing defaults. Every field optional; consumers
    /// fall back to `WorkspaceSettings.standard` values per field.
    public struct WorkspaceSettings: Codable, Equatable, Sendable {
        /// New-icon artboard size (viewBox `0 0 w h`).
        public var iconWidth: Double?
        public var iconHeight: Double?
        /// Editor grid spacing in artboard units; nil hides the grid.
        public var gridSpacing: Double?
        /// Light subdivision lines per grid cell (0/nil = none).
        public var gridSubdivisions: Int?
        /// Snap dragged anchors/shapes to the grid.
        public var snapToGrid: Bool?
        /// Grid line strength multiplier (1 = the editor's standard look;
        /// lower fades the grid, higher darkens it). nil = 1.
        public var gridOpacity: Double?
        /// Grid line colour as "#rrggbb"; nil = the editor's standard
        /// slate blue-grey.
        public var gridColor: String?
        /// Defaults applied to newly drawn shapes and new icons.
        public var defaultStrokeColor: String?
        public var defaultStrokeWidth: Double?
        public var defaultFill: String?
        /// Name of the workspace SVG drawn dimmed behind every icon in the
        /// editor (a shared construction guide); nil = no guide configured.
        public var guideIcon: String?
        /// Whether the guide icon is currently shown.
        public var showGuide: Bool?

        public init(
            iconWidth: Double? = nil, iconHeight: Double? = nil, gridSpacing: Double? = nil,
            gridSubdivisions: Int? = nil, snapToGrid: Bool? = nil, gridOpacity: Double? = nil,
            gridColor: String? = nil,
            defaultStrokeColor: String? = nil, defaultStrokeWidth: Double? = nil,
            defaultFill: String? = nil, guideIcon: String? = nil, showGuide: Bool? = nil
        ) {
            self.iconWidth = iconWidth
            self.iconHeight = iconHeight
            self.gridSpacing = gridSpacing
            self.gridSubdivisions = gridSubdivisions
            self.snapToGrid = snapToGrid
            self.gridOpacity = gridOpacity
            self.gridColor = gridColor
            self.defaultStrokeColor = defaultStrokeColor
            self.defaultStrokeWidth = defaultStrokeWidth
            self.defaultFill = defaultFill
            self.guideIcon = guideIcon
            self.showGuide = showGuide
        }

        /// Fekthor's fallbacks, matching the open-icon conventions the
        /// user draws with (24pt artboard, stroke-first icons).
        public static let standard = WorkspaceSettings(
            iconWidth: 24, iconHeight: 24, gridSpacing: 1, gridSubdivisions: 0,
            snapToGrid: false, gridOpacity: 1.0, defaultStrokeColor: "#010101",
            defaultStrokeWidth: 2, defaultFill: "none")
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
