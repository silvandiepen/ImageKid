import XCTest
@testable import cutout

final class ArgumentsTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CutoutArgumentsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testWatchParsesFolderAndKeepsDestinationAsDirectory() throws {
        let inbox = temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let arguments = try Arguments.parse(["watch", inbox.path, temporaryDirectory.appendingPathComponent("Output").path, "--quality=best"])

        XCTAssertEqual(arguments.watchFolder, inbox.standardizedFileURL)
        XCTAssertTrue(arguments.inputs.isEmpty)
        XCTAssertTrue(arguments.destinationIsDirectory)
        XCTAssertEqual(arguments.quality, .best)
    }

    func testWatchRejectsItsOwnFolderAsDestination() throws {
        let inbox = temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        XCTAssertThrowsError(try Arguments.parse(["watch", inbox.path, inbox.path])) { error in
            XCTAssertEqual((error as? ArgumentError)?.errorDescription, "The watch destination must be different from the watch folder.")
        }
    }
}
