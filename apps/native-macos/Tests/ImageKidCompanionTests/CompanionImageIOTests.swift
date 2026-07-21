import CoreGraphics
import XCTest

final class CompanionImageIOTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageKidCompanionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testDestinationUsesSiblingFolderAndAvoidsCollision() throws {
        let source = temporaryDirectory.appendingPathComponent("photo.png")
        FileManager.default.createFile(atPath: source.path, contents: Data())

        let first = try CompanionImageIO.destinationURL(
            for: source,
            operationFolderName: "ImageKid Upscaled",
            suffix: "-2x",
            extension: "png",
            customFolder: nil,
            overwriteOriginals: false
        )
        XCTAssertEqual(first.lastPathComponent, "photo-2x.png")
        XCTAssertEqual(first.deletingLastPathComponent().lastPathComponent, "ImageKid Upscaled")

        FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = try CompanionImageIO.destinationURL(
            for: source,
            operationFolderName: "ImageKid Upscaled",
            suffix: "-2x",
            extension: "png",
            customFolder: nil,
            overwriteOriginals: false
        )
        XCTAssertEqual(second.lastPathComponent, "photo-2x-2.png")
    }

    func testOverwriteReturnsOriginalWhenExtensionMatches() throws {
        let source = temporaryDirectory.appendingPathComponent("asset.png")
        FileManager.default.createFile(atPath: source.path, contents: Data())

        let destination = try CompanionImageIO.destinationURL(
            for: source,
            operationFolderName: "ImageKid Cutouts",
            suffix: "-cutout",
            extension: "png",
            customFolder: temporaryDirectory.appendingPathComponent("Output", isDirectory: true),
            overwriteOriginals: true
        )

        XCTAssertEqual(destination, source)
    }

    func testOverwriteFallsBackToPNGWhenTransparencyWouldNotFitOriginalFormat() throws {
        let source = temporaryDirectory.appendingPathComponent("portrait.jpg")
        FileManager.default.createFile(atPath: source.path, contents: Data())

        let destination = try CompanionImageIO.destinationURL(
            for: source,
            operationFolderName: "ImageKid Cutouts",
            suffix: "-cutout",
            extension: "png",
            customFolder: nil,
            overwriteOriginals: true
        )

        XCTAssertEqual(destination.lastPathComponent, "portrait-cutout.png")
        XCTAssertEqual(destination.deletingLastPathComponent().lastPathComponent, "ImageKid Cutouts")
    }

    func testPNGWriteRoundTripsAlpha() throws {
        let source = try makeTestImage()
        let output = temporaryDirectory.appendingPathComponent("alpha.png")

        try CompanionImageIO.writePNG(source, to: output)
        let restored = try CompanionImageIO.loadImage(at: output)

        XCTAssertEqual(restored.width, 2)
        XCTAssertEqual(restored.height, 2)
        XCTAssertTrue(restored.alphaInfo != .none)
    }

    private func makeTestImage() throws -> CGImage {
        let width = 2
        let height = 2
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data: [UInt8] = [
            255, 0, 0, 255,
            0, 255, 0, 128,
            0, 0, 255, 64,
            255, 255, 255, 0
        ]
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let image = context.makeImage()
        else {
            XCTFail("Could not create test image")
            throw CompanionProcessingError.unreadableImage
        }
        return image
    }
}
