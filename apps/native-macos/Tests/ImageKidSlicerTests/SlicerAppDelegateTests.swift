import AppKit
import XCTest
@testable import ImageKidSlicer

@MainActor
final class SlicerAppDelegateTests: XCTestCase {
    func testLaunchOpenRequestIsReplayedAfterTheModelAttaches() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlicerAppDelegateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let imageURL = folder.appendingPathComponent("launch.png")
        try TestImages.write(try TestImages.halves(width: 40, height: 20), as: .png, to: imageURL)

        let delegate = SlicerAppDelegate()
        delegate.application(NSApplication.shared, open: [imageURL])

        let model = SlicerDocumentModel()
        delegate.attach(model)

        for _ in 0..<200 where model.images.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.images.map(\.source.displayName), ["launch"])
    }
}
