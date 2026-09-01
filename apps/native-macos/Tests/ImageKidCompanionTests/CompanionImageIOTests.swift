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
        XCTAssertEqual(first.lastPathComponent, "photo.png")
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
        XCTAssertEqual(second.lastPathComponent, "photo-2.png")
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

        XCTAssertEqual(destination.lastPathComponent, "portrait.png")
        XCTAssertEqual(destination.deletingLastPathComponent().lastPathComponent, "ImageKid Cutouts")
    }

    func testPlannedDestinationIgnoresAnExistingFile() {
        let source = temporaryDirectory.appendingPathComponent("photo.jpg")
        let output = temporaryDirectory
            .appendingPathComponent("ImageKid Cutouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: output.appendingPathComponent("photo.png").path,
            contents: Data()
        )

        let planned = CompanionImageIO.plannedDestinationURL(
            for: source,
            operationFolderName: "ImageKid Cutouts",
            suffix: "-cutout",
            extension: "png",
            customFolder: nil,
            overwriteOriginals: false
        )

        XCTAssertEqual(planned.lastPathComponent, "photo.png")
    }

    func testSuffixIsKeptOnlyWhenTheResultLandsBesideTheOriginal() {
        let source = temporaryDirectory.appendingPathComponent("photo.jpg")

        let beside = CompanionImageIO.plannedDestinationURL(
            for: source,
            operationFolderName: "ImageKid Cutouts",
            suffix: "-cutout",
            extension: "png",
            customFolder: temporaryDirectory,
            overwriteOriginals: false
        )
        XCTAssertEqual(beside.lastPathComponent, "photo-cutout.png")

        let elsewhere = CompanionImageIO.plannedDestinationURL(
            for: source,
            operationFolderName: "ImageKid Cutouts",
            suffix: "-cutout",
            extension: "png",
            customFolder: temporaryDirectory.appendingPathComponent("Output", isDirectory: true),
            overwriteOriginals: false
        )
        XCTAssertEqual(elsewhere.lastPathComponent, "photo.png")
    }

    func testOverwriteExistingKeepsThePlannedName() throws {
        let source = temporaryDirectory.appendingPathComponent("photo.jpg")
        let folder = temporaryDirectory.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent("photo.png").path,
            contents: Data()
        )

        let destination = try CompanionImageIO.destinationURL(
            for: source,
            operationFolderName: "ImageKid Cutouts",
            suffix: "-cutout",
            extension: "png",
            customFolder: folder,
            overwriteOriginals: false,
            overwriteExisting: true
        )

        XCTAssertEqual(destination.lastPathComponent, "photo.png")
    }

    /// The defect behind a batch of perfectly-masked black silhouettes: a `CGImage` made
    /// from a URL decodes lazily, so a file moved by a When Done action between load and
    /// use produced black pixels instead of an error.
    func testLoadedImageSurvivesItsFileBeingMoved() throws {
        let source = temporaryDirectory.appendingPathComponent("red.png")
        try CompanionImageIO.writePNG(try makeOpaqueRedImage(), to: source)

        let image = try CompanionImageIO.loadImage(at: source)
        try FileManager.default.removeItem(at: source)

        var pixels = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(pixels.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        })
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        XCTAssertGreaterThan(Int(pixels[0]), 200, "the red channel must survive the file going away")
        XCTAssertEqual(Int(pixels[3]), 255)
    }

    func testLoadingAMissingFileReportsIt() {
        let missing = temporaryDirectory.appendingPathComponent("nope.png")
        XCTAssertThrowsError(try CompanionImageIO.loadImage(at: missing)) { error in
            guard case CompanionProcessingError.sourceMissing = error else {
                return XCTFail("expected sourceMissing, got \(error)")
            }
        }
    }

    private func makeOpaqueRedImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try XCTUnwrap(context.makeImage())
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
