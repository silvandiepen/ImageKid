import XCTest
@testable import cutout

final class ImageFolderScannerTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CutoutFolderScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testFindsSupportedFilesOnlyAtTheWatchedLevel() throws {
        FileManager.default.createFile(atPath: folder.appendingPathComponent("b.jpg").path, contents: Data())
        FileManager.default.createFile(atPath: folder.appendingPathComponent("a.PNG").path, contents: Data())
        FileManager.default.createFile(atPath: folder.appendingPathComponent("notes.txt").path, contents: Data())
        let nested = folder.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: nested.appendingPathComponent("hidden.jpg").path, contents: Data())

        XCTAssertEqual(ImageFolderScanner.images(in: folder).map(\.lastPathComponent), ["a.PNG", "b.jpg"])
    }
}
