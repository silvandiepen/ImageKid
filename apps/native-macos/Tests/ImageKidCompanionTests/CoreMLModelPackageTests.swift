import Foundation
import XCTest

final class CoreMLModelPackageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageKidModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testCompleteCoreMLPackageIsAccepted() throws {
        let package = temporaryDirectory.appendingPathComponent("Model.mlpackage", isDirectory: true)
        try createRequiredFiles(in: package)

        XCTAssertTrue(CoreMLModel.isValidPackage(at: package))
    }

    func testPackageMissingARequiredFileIsRejected() throws {
        let package = temporaryDirectory.appendingPathComponent("Model.mlpackage", isDirectory: true)
        try createRequiredFiles(in: package)
        try FileManager.default.removeItem(
            at: package.appendingPathComponent("Data/com.apple.CoreML/weights/weight.bin")
        )

        XCTAssertFalse(CoreMLModel.isValidPackage(at: package))
    }

    private func createRequiredFiles(in package: URL) throws {
        for relativePath in CoreMLModel.requiredFiles {
            let file = package.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data("test".utf8)))
        }
    }
}
