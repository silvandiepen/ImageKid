import Foundation
import XCTest
@testable import ImageKid

final class BackgroundRemovalAssetVerifierTests: XCTestCase {
    func testSHA256HexMatchesKnownFixture() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageKidVerifier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("fixture.bin")
        try Data("imagekid".utf8).write(to: url)

        XCTAssertEqual(
            try BackgroundRemovalAssetVerifier.sha256Hex(for: url),
            "783bd4f442b83f3efe7d5aefaf4369460ce43065fd0145d3b8119bbd58f8ec9c"
        )
    }

    func testBackgroundRemovalAddOnUsesPinnedPackageVersion() {
        XCTAssertEqual(BackgroundRemovalModelConfiguration.rembgVersion, "2.0.76")
        XCTAssertEqual(BackgroundRemovalModelConfiguration.rembgPackageRequirement, "rembg[cpu,cli]==2.0.76")
        XCTAssertEqual(BackgroundRemovalModelConfiguration.minimumPythonVersion, PythonVersion(major: 3, minor: 11))
    }

    func testBackgroundRemovalModelPinIsComplete() {
        XCTAssertEqual(BackgroundRemovalModelConfiguration.modelByteCount, 178_648_008)
        XCTAssertEqual(BackgroundRemovalModelConfiguration.modelSHA256.count, 64)
    }

    func testPythonVersionParsesStandardOutput() {
        XCTAssertEqual(PythonVersion(versionOutput: "Python 3.11.9"), PythonVersion(major: 3, minor: 11, patch: 9))
        XCTAssertEqual(PythonVersion(versionOutput: "Python 3.12"), PythonVersion(major: 3, minor: 12))
        XCTAssertNil(PythonVersion(versionOutput: "not python"))
    }

    func testPythonVersionOrderingUsesPatchLevel() {
        XCTAssertLessThan(PythonVersion(major: 3, minor: 10, patch: 12), PythonVersion(major: 3, minor: 11))
        XCTAssertLessThan(PythonVersion(major: 3, minor: 11), PythonVersion(major: 3, minor: 11, patch: 1))
        XCTAssertGreaterThan(PythonVersion(major: 3, minor: 12), PythonVersion(major: 3, minor: 11, patch: 99))
    }
}
