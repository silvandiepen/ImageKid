import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ImageKidSlicer

final class SliceImageIOTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageKidSlicerIOTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
    }

    func testEXIFRotationIsBakedInSoGeometryMatchesWhatTheUserSees() throws {
        let url = folder.appendingPathComponent("rotated.jpg")
        // Orientation 6 = rotate 90° clockwise on display, so a 40×20 stored
        // image is a 20×40 image to the user — and to every slice rectangle.
        try TestImages.write(
            TestImages.halves(width: 40, height: 20),
            as: .jpeg,
            to: url,
            orientation: .right
        )

        let source = try SliceImageIO.imageSource(at: url)
        XCTAssertEqual(SliceImageIO.orientation(of: source), .right)

        let oriented = try SliceImageIO.loadOrientedImage(from: source)
        XCTAssertEqual(oriented.width, 20)
        XCTAssertEqual(oriented.height, 40)
    }

    func testUnrotatedImageLoadsAtItsStoredSize() throws {
        let url = folder.appendingPathComponent("plain.png")
        try TestImages.write(TestImages.halves(width: 64, height: 32), as: .png, to: url)

        let source = try SliceImageIO.imageSource(at: url)
        let image = try SliceImageIO.loadOrientedImage(from: source)
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 32)
    }

    func testWritableSourceFormatsArePreserved() throws {
        for (type, expected) in [(UTType.png, "png"), (.jpeg, "jpeg"), (.tiff, "tiff")] {
            let url = folder.appendingPathComponent("sample.\(expected)")
            try TestImages.write(TestImages.halves(width: 20, height: 20), as: type, to: url)
            let output = SliceImageIO.outputType(for: try SliceImageIO.imageSource(at: url))
            XCTAssertEqual(output.type, type)
        }
    }

    func testUnwritableSourceFormatFallsBackToPNG() throws {
        let url = folder.appendingPathComponent("sample.gif")
        try TestImages.write(TestImages.halves(width: 20, height: 20), as: .gif, to: url)

        let output = SliceImageIO.outputType(for: try SliceImageIO.imageSource(at: url))
        XCTAssertEqual(output.type, .png)
        XCTAssertEqual(output.fileExtension, "png")
    }

    func testAtomicWriteLeavesNoTemporaryFileBehind() throws {
        let destination = folder.appendingPathComponent("out.png")
        try SliceImageIO.writeAtomically(TestImages.halves(width: 10, height: 10), to: destination, type: .png)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(".") }
        XCTAssertTrue(leftovers.isEmpty, "Found stray temporary files: \(leftovers)")
    }

    func testPreviewIsCappedToTheRequestedSize() throws {
        let url = folder.appendingPathComponent("big.png")
        try TestImages.write(TestImages.halves(width: 600, height: 300), as: .png, to: url)

        let preview = try XCTUnwrap(SliceImageIO.preview(from: SliceImageIO.imageSource(at: url), maxPixelSize: 100))
        XCTAssertEqual(max(preview.width, preview.height), 100)
    }
}
