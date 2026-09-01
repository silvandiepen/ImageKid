import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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

    func testWriteAtomicallyReplacesExistingFileWithoutLeavingTemporaryOutput() throws {
        let output = temporaryDirectory.appendingPathComponent("existing.png")
        try Data("previous contents".utf8).write(to: output)

        try CompanionImageIO.writePNG(makeTestImage(), to: output)

        let restored = try CompanionImageIO.loadImage(at: output)
        XCTAssertEqual(restored.width, 2)
        XCTAssertEqual(restored.height, 2)
        let remaining = try FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.lastPathComponent, output.lastPathComponent)
    }

    func testLoadAndPropertiesApplyEncodedOrientation() throws {
        let source = temporaryDirectory.appendingPathComponent("rotated.jpeg")
        try writeOrientedJPEG(makeTestImage(width: 2, height: 3), orientation: 6, to: source)

        let properties = try XCTUnwrap(CompanionImageIO.properties(at: source))
        let loaded = try CompanionImageIO.loadImage(at: source)

        XCTAssertEqual(properties.width, 3)
        XCTAssertEqual(properties.height, 2)
        XCTAssertEqual(loaded.width, 3)
        XCTAssertEqual(loaded.height, 2)
    }

    private func makeTestImage(width: Int = 2, height: Int = 2) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        for pixel in 0..<(width * height) {
            data[pixel * 4] = UInt8((pixel * 31) % 255)
            data[pixel * 4 + 1] = UInt8((pixel * 67) % 255)
            data[pixel * 4 + 2] = UInt8((pixel * 101) % 255)
            data[pixel * 4 + 3] = pixel == 0 ? 128 : 255
        }
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

    private func writeOrientedJPEG(_ image: CGImage, orientation: Int, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CompanionProcessingError.cannotWriteImage
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw CompanionProcessingError.cannotWriteImage
        }
    }
}
