import XCTest

final class SourceFileActionTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var sourceFolder: URL!
    private var actionFolder: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceFileActionTests-\(UUID().uuidString)", isDirectory: true)
        sourceFolder = temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        actionFolder = temporaryDirectory.appendingPathComponent("Processed", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    private func makeSource(_ name: String, in folder: URL? = nil, contents: String = "original") -> URL {
        let url = (folder ?? sourceFolder).appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(contents.utf8))
        return url
    }

    func testKeepLeavesTheFileAlone() throws {
        let source = makeSource("photo.jpg")

        let outcome = try SourceFileActionRunner.apply(.keep, to: source, folder: actionFolder)

        XCTAssertEqual(outcome, .kept(reason: nil))
        XCTAssertNil(outcome.note)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMoveRelocatesTheFileAndCreatesTheFolder() throws {
        let source = makeSource("photo.jpg")

        let outcome = try SourceFileActionRunner.apply(.move, to: source, folder: actionFolder)

        guard case .relocated(let moved) = outcome else {
            return XCTFail("Expected the source to be relocated, got \(outcome)")
        }
        XCTAssertEqual(moved, actionFolder.appendingPathComponent("photo.jpg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(outcome.note, "Original moved to \u{201C}Processed\u{201D}")
    }

    func testMoveNeverOverwritesAFileAlreadyInTheFolder() throws {
        try FileManager.default.createDirectory(at: actionFolder, withIntermediateDirectories: true)
        let existing = makeSource("photo.jpg", in: actionFolder, contents: "already there")
        let source = makeSource("photo.jpg", contents: "the new one")

        let outcome = try SourceFileActionRunner.apply(.move, to: source, folder: actionFolder)

        guard case .relocated(let moved) = outcome else {
            return XCTFail("Expected the source to be relocated, got \(outcome)")
        }
        XCTAssertEqual(moved.lastPathComponent, "photo-2.jpg")
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "already there")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "the new one")
    }

    func testMoveIntoTheFolderTheFileIsAlreadyInIsANoOp() throws {
        let source = makeSource("photo.jpg")

        let outcome = try SourceFileActionRunner.apply(.move, to: source, folder: sourceFolder)

        XCTAssertEqual(outcome, .kept(reason: "Original is already in that folder"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCopyLeavesTheOriginalInPlace() throws {
        let source = makeSource("photo.jpg")

        let outcome = try SourceFileActionRunner.apply(.copy, to: source, folder: actionFolder)

        guard case .copied(let copy) = outcome else {
            return XCTFail("Expected the source to be copied, got \(outcome)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMoveWithoutAFolderReportsTheMissingSetting() throws {
        let source = makeSource("photo.jpg")

        XCTAssertThrowsError(try SourceFileActionRunner.apply(.move, to: source, folder: nil)) { error in
            XCTAssertEqual(
                (error as? SourceFileActionError)?.errorDescription,
                "Choose a folder for the originals under When Done."
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testDeleteRemovesTheFile() throws {
        let source = makeSource("photo.jpg")

        let outcome = try SourceFileActionRunner.apply(.delete, to: source, folder: nil)

        XCTAssertEqual(outcome, .deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testDeleteOnAMissingFileReportsInsteadOfCrashing() throws {
        let missing = sourceFolder.appendingPathComponent("gone.jpg")

        XCTAssertThrowsError(try SourceFileActionRunner.apply(.delete, to: missing, folder: nil)) { error in
            XCTAssertTrue(
                error.localizedDescription.hasPrefix("Could not delete the original:"),
                "Unexpected message: \(error.localizedDescription)"
            )
        }
    }

    func testOnlyRemovingActionsNeedWriteAccessToTheSourceFolder() {
        XCTAssertEqual(SourceFileAction.allCases.filter(\.removesOriginal), [.move, .trash, .delete])
        XCTAssertEqual(SourceFileAction.allCases.filter(\.needsFolder), [.move, .copy])
        XCTAssertNil(SourceFileAction.keep.warning)
        XCTAssertNotNil(SourceFileAction.delete.warning)
    }
}
