import XCTest

@testable import FekthorKit

final class WorkspaceTests: XCTestCase {
    private var base: URL!
    /// The scanned icons folder (`<base>/src/icons`).
    private var iconsDir: URL!
    /// Sibling metadata folder (`<base>/src/meta`).
    private var metaDir: URL!

    private static let svgBody =
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\"><rect width=\"24\" height=\"24\"/></svg>"

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("fekthor-workspace-\(UUID().uuidString)")
        iconsDir = base.appendingPathComponent("src/icons")
        metaDir = base.appendingPathComponent("src/meta")
        try FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)

        // Two categories + one uncategorized root SVG + noise that must be ignored.
        try addIcon("icon_add", category: "ui", tags: ["plus", "create"], title: "Add")
        try addIcon("icon_menu", category: "ui", tags: ["hamburger", "navigation"], title: "Menu")
        try addIcon("icon_cat", category: "animals", tags: ["pet", "feline"], title: "Cat")
        try addIcon("icon_cafe", category: "animals", tags: ["café", "coffee"], title: "Café")
        try addIcon("icon_loose", category: "", tags: nil, title: nil)  // no meta
        try write("not-an-icon.txt", in: iconsDir.appendingPathComponent("ui"), contents: "nope")
        try write(".hidden.svg", in: iconsDir, contents: Self.svgBody)
    }

    override func tearDownWithError() throws {
        if let base { try? FileManager.default.removeItem(at: base) }
    }

    // MARK: - Helpers

    /// Creates `<category>/<name>.svg` (or root when category is "") and,
    /// when tags/title are given, a matching flat `meta/<name>.svg.json`.
    private func addIcon(
        _ name: String, category: String, tags: [String]?, title: String?
    ) throws {
        let folder =
            category.isEmpty ? iconsDir! : iconsDir.appendingPathComponent(category)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write(name + ".svg", in: folder, contents: Self.svgBody)
        guard tags != nil || title != nil else { return }
        var meta: [String: Any] = ["description": "test icon", "category": ["Test"]]
        if let tags { meta["tag"] = tags }
        if let title { meta["title"] = title }
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys])
        try data.write(to: metaDir.appendingPathComponent(name + ".svg.json"))
    }

    private func write(_ name: String, in folder: URL, contents: String) throws {
        try contents.data(using: .utf8)!.write(to: folder.appendingPathComponent(name))
    }

    private func scan() throws -> Workspace { try Workspace.scan(iconsDir) }

    private func entry(_ name: String, in ws: Workspace) throws -> IconEntry {
        try XCTUnwrap(ws.entries.first { $0.name == name }, "missing entry \(name)")
    }

    // MARK: - Scan

    func testScanShapeAndDeterminism() throws {
        let ws = try scan()
        XCTAssertEqual(ws.categories, ["animals", "ui"])
        XCTAssertEqual(
            ws.entries.map(\.id),
            ["icon_loose", "animals/icon_cafe", "animals/icon_cat", "ui/icon_add", "ui/icon_menu"])
        XCTAssertEqual(ws.entries(in: "").map(\.name), ["icon_loose"])
        XCTAssertEqual(ws.entries(in: "ui").map(\.name), ["icon_add", "icon_menu"])
        XCTAssertNotNil(ws.metaFolder)

        // Non-SVG and hidden files ignored.
        XCTAssertFalse(ws.entries.contains { $0.name.contains("hidden") || $0.name.contains("not") })
        // Attributes populated.
        let add = try entry("icon_add", in: ws)
        XCTAssertEqual(add.fileSize, Self.svgBody.utf8.count)
        XCTAssertGreaterThan(add.modificationDate, .distantPast)
        XCTAssertEqual(add.fileName, "icon_add.svg")

        // Deterministic: a second scan is byte-for-byte equal.
        XCTAssertEqual(try scan(), ws)
    }

    func testScanRejectsNonDirectory() throws {
        XCTAssertThrowsError(
            try Workspace.scan(base.appendingPathComponent("does-not-exist"))
        ) { error in
            guard case WorkspaceError.notADirectory = error else {
                return XCTFail("expected notADirectory, got \(error)")
            }
        }
    }

    func testEmptyCategoryFolderIsListed() throws {
        try FileManager.default.createDirectory(
            at: iconsDir.appendingPathComponent("empty"), withIntermediateDirectories: false)
        XCTAssertEqual(try scan().categories, ["animals", "empty", "ui"])
    }

    // MARK: - Metadata

    func testMetadataAdoption() throws {
        let ws = try scan()
        let meta = try XCTUnwrap(ws.metadata(for: try entry("icon_add", in: ws)))
        XCTAssertEqual(meta.title, "Add")
        XCTAssertEqual(meta.tag, ["plus", "create"])
        XCTAssertEqual(meta.category, ["Test"])
        XCTAssertEqual(meta.description, "test icon")
        // Entry without a meta file.
        XCTAssertNil(ws.metadata(for: try entry("icon_loose", in: ws)))
    }

    func testMetadataToleratesPartialJSON() throws {
        try "{\"tag\": \"single\"}".data(using: .utf8)!
            .write(to: metaDir.appendingPathComponent("icon_loose.svg.json"))
        let ws = try scan()
        let meta = try XCTUnwrap(ws.metadata(for: try entry("icon_loose", in: ws)))
        XCTAssertEqual(meta.tag, ["single"])
        XCTAssertNil(meta.title)
        XCTAssertEqual(meta.category, [])
    }

    func testNoMetaFolderDetectedOutsideLayout() throws {
        let lone = base.appendingPathComponent("standalone")
        try FileManager.default.createDirectory(at: lone, withIntermediateDirectories: true)
        try write("solo.svg", in: lone, contents: Self.svgBody)
        let ws = try Workspace.scan(lone)
        XCTAssertNil(ws.metaFolder)
        XCTAssertNil(ws.metadata(for: try entry("solo", in: ws)))
    }

    // MARK: - Rename

    func testRenameMovesSVGAndMeta() throws {
        let ws = try scan()
        let change = try ws.rename(try entry("icon_add", in: ws), to: "icon_plus")
        let fm = FileManager.default
        XCTAssertEqual(change.svg.lastPathComponent, "icon_plus.svg")
        XCTAssertEqual(change.meta?.lastPathComponent, "icon_plus.svg.json")
        XCTAssertTrue(fm.fileExists(atPath: change.svg.path))
        XCTAssertTrue(fm.fileExists(atPath: change.meta!.path))
        XCTAssertFalse(fm.fileExists(atPath: iconsDir.appendingPathComponent("ui/icon_add.svg").path))
        XCTAssertFalse(fm.fileExists(atPath: metaDir.appendingPathComponent("icon_add.svg.json").path))
        // Metadata follows the new name on rescan.
        let ws2 = try scan()
        XCTAssertEqual(try ws2.metadata(for: entry("icon_plus", in: ws2))?.title, "Add")
    }

    func testRenameWithoutMeta() throws {
        let ws = try scan()
        let change = try ws.rename(try entry("icon_loose", in: ws), to: "icon_free")
        XCTAssertNil(change.meta)
        XCTAssertTrue(FileManager.default.fileExists(atPath: change.svg.path))
    }

    func testRenameRefusesCollision() throws {
        let ws = try scan()
        XCTAssertThrowsError(try ws.rename(try entry("icon_add", in: ws), to: "icon_menu")) {
            guard case WorkspaceError.targetExists = $0 else {
                return XCTFail("expected targetExists, got \($0)")
            }
        }
        // Nothing changed on disk.
        XCTAssertEqual(try scan(), ws)
    }

    func testRenameRefusesInvalidName() throws {
        let ws = try scan()
        let victim = try entry("icon_add", in: ws)
        for bad in ["", ".sneaky", "a/b", "a\\b"] {
            XCTAssertThrowsError(try ws.rename(victim, to: bad), "name: \(bad)") {
                guard case WorkspaceError.invalidName = $0 else {
                    return XCTFail("expected invalidName for \(bad), got \($0)")
                }
            }
        }
    }

    // MARK: - Move

    func testMoveToExistingCategory() throws {
        let ws = try scan()
        let change = try ws.move(try entry("icon_cat", in: ws), toCategory: "ui")
        XCTAssertEqual(change.svg, iconsDir.appendingPathComponent("ui/icon_cat.svg"))
        let ws2 = try scan()
        XCTAssertEqual(ws2.entries(in: "ui").map(\.name), ["icon_add", "icon_cat", "icon_menu"])
        // Flat metadata still resolves after the move.
        XCTAssertEqual(try ws2.metadata(for: entry("icon_cat", in: ws2))?.title, "Cat")
    }

    func testMoveCreatesCategoryAndMoveToRoot() throws {
        let ws = try scan()
        _ = try ws.move(try entry("icon_menu", in: ws), toCategory: "navigation")
        _ = try ws.move(try entry("icon_cat", in: ws), toCategory: "")
        let ws2 = try scan()
        XCTAssertTrue(ws2.categories.contains("navigation"))
        XCTAssertEqual(ws2.entries(in: "navigation").map(\.name), ["icon_menu"])
        XCTAssertEqual(ws2.entries(in: "").map(\.name), ["icon_cat", "icon_loose"])
    }

    func testMoveRefusesCollision() throws {
        let ws = try scan()
        // Same stem in both categories.
        try addIcon("icon_cat", category: "ui", tags: nil, title: nil)
        XCTAssertThrowsError(try ws.move(try entry("icon_cat", in: ws), toCategory: "ui")) {
            guard case WorkspaceError.targetExists = $0 else {
                return XCTFail("expected targetExists, got \($0)")
            }
        }
        // Source untouched.
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: iconsDir.appendingPathComponent("animals/icon_cat.svg").path))
    }

    // MARK: - New category

    func testNewCategory() throws {
        let ws = try scan()
        let url = try ws.newCategory("wayfinding")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertThrowsError(try ws.newCategory("wayfinding")) {
            guard case WorkspaceError.categoryExists = $0 else {
                return XCTFail("expected categoryExists, got \($0)")
            }
        }
        XCTAssertThrowsError(try ws.newCategory("a/b")) {
            guard case WorkspaceError.invalidName = $0 else {
                return XCTFail("expected invalidName, got \($0)")
            }
        }
    }

    // MARK: - Delete

    func testDeleteTrashesSVGAndMeta() throws {
        let ws = try scan()
        let victim = try entry("icon_menu", in: ws)
        do {
            let change = try ws.delete(victim)
            XCTAssertFalse(FileManager.default.fileExists(atPath: victim.url.path))
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: metaDir.appendingPathComponent("icon_menu.svg.json").path))
            XCTAssertNotEqual(change.svg, victim.url)
        } catch WorkspaceError.trashUnavailable {
            // Sandboxed test environments may have no trash; the contract is
            // then "throw, delete nothing".
            XCTAssertTrue(FileManager.default.fileExists(atPath: victim.url.path))
            throw XCTSkip("system trash unavailable in this environment")
        }
    }

    func testDeleteMissingFileThrows() throws {
        let ws = try scan()
        let victim = try entry("icon_menu", in: ws)
        try FileManager.default.removeItem(at: victim.url)
        XCTAssertThrowsError(try ws.delete(victim)) {
            guard case WorkspaceError.fileNotFound = $0 else {
                return XCTFail("expected fileNotFound, got \($0)")
            }
        }
    }

    // MARK: - Duplicate

    func testDuplicateCopiesSVGAndMeta() throws {
        let ws = try scan()
        let source = try entry("icon_add", in: ws)
        let first = try ws.duplicate(source)
        XCTAssertEqual(first.svg.lastPathComponent, "icon_add copy.svg")
        XCTAssertEqual(first.meta?.lastPathComponent, "icon_add copy.svg.json")
        // Second duplicate picks the next free slot instead of overwriting.
        let second = try ws.duplicate(source)
        XCTAssertEqual(second.svg.lastPathComponent, "icon_add copy 2.svg")
        let ws2 = try scan()
        XCTAssertEqual(
            ws2.entries(in: "ui").map(\.name),
            ["icon_add", "icon_add copy", "icon_add copy 2", "icon_menu"])
        XCTAssertEqual(try ws2.metadata(for: entry("icon_add copy", in: ws2))?.title, "Add")
        // Original untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.url.path))
    }

    func testDuplicateWithoutMeta() throws {
        let ws = try scan()
        let change = try ws.duplicate(try entry("icon_loose", in: ws))
        XCTAssertEqual(change.svg.lastPathComponent, "icon_loose copy.svg")
        XCTAssertNil(change.meta)
    }

    // MARK: - Diff

    func testDiff() throws {
        let old = try scan()
        XCTAssertTrue(Workspace.diff(old: old, new: old).isEmpty)

        // Add one, remove one, modify one.
        try addIcon("icon_dog", category: "animals", tags: ["pet"], title: "Dog")
        try FileManager.default.removeItem(
            at: iconsDir.appendingPathComponent("ui/icon_menu.svg"))
        let modifiedURL = iconsDir.appendingPathComponent("ui/icon_add.svg")
        try (Self.svgBody + "<!-- changed -->").data(using: .utf8)!.write(to: modifiedURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000_000_000)],
            ofItemAtPath: modifiedURL.path)

        let new = try scan()
        let diff = Workspace.diff(old: old, new: new)
        XCTAssertEqual(diff.added.map(\.id), ["animals/icon_dog"])
        XCTAssertEqual(diff.removed.map(\.id), ["ui/icon_menu"])
        XCTAssertEqual(diff.modified.map(\.id), ["ui/icon_add"])
        // `modified` carries the NEW version.
        XCTAssertEqual(
            diff.modified[0].modificationDate, Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertFalse(diff.isEmpty)
    }

    func testDiffTreatsMoveAsRemoveAndAdd() throws {
        let old = try scan()
        _ = try old.move(try entry("icon_cat", in: old), toCategory: "ui")
        let diff = Workspace.diff(old: old, new: try scan())
        XCTAssertEqual(diff.added.map(\.id), ["ui/icon_cat"])
        XCTAssertEqual(diff.removed.map(\.id), ["animals/icon_cat"])
        XCTAssertEqual(diff.modified, [])
    }

    // MARK: - Search

    func testSearch() throws {
        let ws = try scan()
        // By name, case-insensitive.
        XCTAssertEqual(ws.search("MENU").map(\.name), ["icon_menu"])
        // By metadata tag.
        XCTAssertEqual(ws.search("hamburger").map(\.name), ["icon_menu"])
        // By metadata title.
        XCTAssertTrue(ws.search("Add").map(\.name).contains("icon_add"))
        // Diacritic-insensitive both ways: plain query hits accented tag…
        XCTAssertTrue(ws.search("cafe").map(\.name).contains("icon_cafe"))
        // …and accented query hits plain names/tags.
        XCTAssertTrue(ws.search("café").map(\.name).contains("icon_cafe"))
        // Empty and whitespace queries return everything, scan-ordered.
        XCTAssertEqual(ws.search("").map(\.id), ws.entries.map(\.id))
        XCTAssertEqual(ws.search("   ").map(\.id), ws.entries.map(\.id))
        // No match.
        XCTAssertEqual(ws.search("zzz-nothing"), [])
    }

    // MARK: - Corpus

    /// Scans the real open-icon corpus when FEKTHOR_ICON_CORPUS points at
    /// its `src/icons` folder (read-only: scan + metadata only, no ops).
    func testCorpusWorkspaceSmoke() throws {
        guard let root = ProcessInfo.processInfo.environment["FEKTHOR_ICON_CORPUS"] else {
            throw XCTSkip("set FEKTHOR_ICON_CORPUS to run")
        }
        let ws = try Workspace.scan(URL(fileURLWithPath: root))
        XCTAssertGreaterThan(ws.entries.count, 800, "expected >800 icons")
        XCTAssertGreaterThan(ws.categories.count, 10, "expected >10 categories")
        XCTAssertNotNil(ws.metaFolder, "open-icon layout should expose src/meta")

        // Every entry is well-formed and metadata parses wherever present.
        var metaCount = 0
        for entry in ws.entries {
            XCTAssertFalse(entry.name.isEmpty)
            XCTAssertGreaterThan(entry.fileSize, 0, entry.id)
            if let meta = ws.metadata(for: entry) {
                metaCount += 1
                XCTAssertFalse(meta.tag.isEmpty && meta.title == nil, entry.id)
            }
        }
        XCTAssertGreaterThan(metaCount, 800, "expected metadata for most icons")
        // Determinism on the real corpus too.
        XCTAssertEqual(try Workspace.scan(URL(fileURLWithPath: root)), ws)
        print("workspace corpus: \(ws.entries.count) icons, \(ws.categories.count) categories, \(metaCount) meta files")
    }
}
// MARK: - Create (new icon)

extension WorkspaceTests {
    func testCreateWritesNewIconAndRefusesCollision() throws {
        let ws = try scan()
        let svg = SVGWriter.write(.blank(width: 24, height: 24))
        let change = try ws.create(name: "icon_new", category: "ui", svg: svg)
        XCTAssertEqual(change.svg.lastPathComponent, "icon_new.svg")
        XCTAssertEqual(try String(contentsOf: change.svg, encoding: .utf8), svg)
        let rescanned = try scan()
        XCTAssertTrue(rescanned.entries.contains { $0.id == "ui/icon_new" })
        XCTAssertThrowsError(try ws.create(name: "icon_new", category: "ui", svg: svg)) {
            guard case WorkspaceError.targetExists = $0 else {
                return XCTFail("expected targetExists, got \($0)")
            }
        }
    }

    func testCreateInNewCategoryAndRoot() throws {
        let ws = try scan()
        let svg = SVGWriter.write(.blank(width: 24, height: 24))
        let inNew = try ws.create(name: "a", category: "fresh", svg: svg)
        XCTAssertTrue(inNew.svg.path.hasSuffix("fresh/a.svg"))
        let atRoot = try ws.create(name: "b", category: "", svg: svg)
        XCTAssertEqual(atRoot.svg.deletingLastPathComponent().path, ws.root.path)
        XCTAssertThrowsError(try ws.create(name: "bad/name", category: "", svg: svg))
    }
}
