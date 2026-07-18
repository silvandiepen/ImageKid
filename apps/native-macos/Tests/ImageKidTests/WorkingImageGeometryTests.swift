import AppKit
import CoreGraphics
import XCTest
@testable import ImageKid

final class WorkingImageGeometryTests: XCTestCase {
    func testDisplayPointMapsIntoAppliedCrop() {
        let crop = CGRect(x: 0.25, y: 0.20, width: 0.50, height: 0.40)
        let result = WorkingImageGeometry.sourcePoint(
            fromDisplayNormalized: CGPoint(x: 0.5, y: 0.5),
            cropRect: crop
        )

        XCTAssertEqual(result.x, 0.50, accuracy: 0.0001)
        XCTAssertEqual(result.y, 0.40, accuracy: 0.0001)
    }

    func testSourceRectRoundTripsThroughDisplayCrop() throws {
        let crop = CGRect(x: 0.20, y: 0.10, width: 0.60, height: 0.70)
        let source = CGRect(x: 0.32, y: 0.24, width: 0.18, height: 0.21)

        let display = try XCTUnwrap(
            WorkingImageGeometry.displayRect(fromSourceNormalized: source, cropRect: crop)
        )
        let roundTrip = WorkingImageGeometry.sourceRect(
            fromDisplayNormalized: display,
            cropRect: crop
        )

        XCTAssertEqual(roundTrip.minX, source.minX, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.minY, source.minY, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.width, source.width, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.height, source.height, accuracy: 0.0001)
    }

    func testFreehandBuilderAlwaysRecordsStartAndEnd() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        let start = CGPoint(x: 20, y: 30)
        let end = CGPoint(x: 120, y: 160)

        let points = FreehandStrokeBuilder.append(
            points: [],
            start: start,
            location: end,
            inside: bounds
        )

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].x, start.x)
        XCTAssertEqual(points[0].y, start.y)
        XCTAssertEqual(points[1].x, end.x)
        XCTAssertEqual(points[1].y, end.y)
    }

    func testCroppedPixelSizeReflectsAppliedCrop() {
        let result = WorkingImageGeometry.croppedPixelSize(
            sourceSize: CGSize(width: 2000, height: 1000),
            cropRect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25)
        )

        XCTAssertEqual(result.width, 1000)
        XCTAssertEqual(result.height, 250)
    }

    @MainActor
    func testTextAndUIUpscaleKeepsExactPixelSize() throws {
        let source = try makeBitmapImage(width: 1000, height: 1000)
        let upscaled = try ImageUpscaleService.upscale(
            source,
            to: CGSize(width: 2000, height: 2000),
            contentMode: .textAndUI
        )
        let session = ImageSession(sourceURL: nil, sourceImage: upscaled)

        XCTAssertEqual(session.pixelSize.width, 2000)
        XCTAssertEqual(session.pixelSize.height, 2000)
        XCTAssertNotNil(upscaled.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    @MainActor
    func testAutomaticUpscaleDetectsTextAndUI() throws {
        let source = try makeBitmapImage(width: 1000, height: 1000)

        XCTAssertEqual(
            ImageUpscaleService.resolvedContentMode(for: source, requestedMode: .automatic),
            .textAndUI
        )
    }

    @MainActor
    func testAutomaticUpscaleDetectsPhotoArtwork() throws {
        let source = try makePhotoLikeImage(width: 1000, height: 1000)

        XCTAssertEqual(
            ImageUpscaleService.resolvedContentMode(for: source, requestedMode: .automatic),
            .photoArtwork
        )
    }

    @MainActor
    func testApplyBestQualityResizeCommitsRequestedPixelSizeOnce() async throws {
        let source = try makeBitmapImage(width: 1254, height: 1254)
        let model = AppModel()
        model.load([try temporaryImageURL(for: source)])

        model.applyResizeToCurrentImage(
            targetSize: CGSize(width: 2508, height: 2508),
            upscaleEngine: .bestQuality,
            upscaleContentMode: .textAndUI
        )

        while model.isApplyingResize {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        guard case .image(let session) = model.media else {
            return XCTFail("Expected image session")
        }
        XCTAssertEqual(session.pixelSize.width, 2508)
        XCTAssertEqual(session.pixelSize.height, 2508)
    }

    @MainActor
    func testDirtyCloseCanBeCancelledOrDiscarded() throws {
        let model = AppModel()
        model.load([try temporaryImageURL(for: makeBitmapImage(width: 64, height: 64))])
        let itemID = try XCTUnwrap(model.selectedItemID)
        guard case .image(let session) = model.media else {
            return XCTFail("Expected image session")
        }
        session.isDirty = true

        model.dirtyCloseConfirmation = { _ in false }
        model.closeItem(itemID)
        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.selectedItemID, itemID)

        model.dirtyCloseConfirmation = { _ in true }
        model.closeItem(itemID)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.selectedItemID)
    }

    @MainActor
    func testSaveWritesOnlyActiveDirtyImage() throws {
        let model = AppModel()
        model.load([
            try temporaryImageURL(for: makeBitmapImage(width: 64, height: 64)),
            try temporaryImageURL(for: makePhotoLikeImage(width: 64, height: 64))
        ])
        let firstID = try XCTUnwrap(model.selectedItemID)
        let secondID = try XCTUnwrap(model.items.last?.id)

        guard case .image(let firstSession) = model.items.first(where: { $0.id == firstID })?.media,
              case .image(let secondSession) = model.items.first(where: { $0.id == secondID })?.media else {
            return XCTFail("Expected image sessions")
        }
        firstSession.isDirty = true
        secondSession.isDirty = true

        model.saveImage()

        guard case .image(let savedFirst) = model.items.first(where: { $0.id == firstID })?.media,
              case .image(let untouchedSecond) = model.items.first(where: { $0.id == secondID })?.media else {
            return XCTFail("Expected image sessions")
        }
        XCTAssertFalse(savedFirst.isDirty)
        XCTAssertTrue(untouchedSecond.isDirty)
    }

    @MainActor
    func testReplacementTargetsStableItemAfterSelectionChanges() throws {
        let model = AppModel()
        model.load([
            try temporaryImageURL(for: makeBitmapImage(width: 64, height: 64)),
            try temporaryImageURL(for: makePhotoLikeImage(width: 64, height: 64))
        ])
        let firstID = try XCTUnwrap(model.selectedItemID)
        let secondID = try XCTUnwrap(model.items.last?.id)
        model.selectItem(secondID)

        let replacement = ImageSession(
            sourceURL: nil,
            sourceImage: try makeBitmapImage(width: 96, height: 80)
        )
        XCTAssertTrue(model.replaceMedia(.image(replacement), for: firstID))

        guard case .image(let firstSession) = model.items.first(where: { $0.id == firstID })?.media,
              case .image(let secondSession) = model.items.first(where: { $0.id == secondID })?.media else {
            return XCTFail("Expected image sessions")
        }
        XCTAssertEqual(firstSession.pixelSize.width, 96)
        XCTAssertEqual(firstSession.pixelSize.height, 80)
        XCTAssertEqual(secondSession.pixelSize.width, 64)
        XCTAssertEqual(secondSession.pixelSize.height, 64)
        XCTAssertEqual(model.selectedItemID, secondID)
    }

    private func makeBitmapImage(width: Int, height: Int) throws -> NSImage {
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw NSError(domain: "ImageKidTests", code: 1)
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor(calibratedWhite: 0.92, alpha: 1).cgColor)
        for y in stride(from: 60, to: height, by: 96) {
            context.fill(CGRect(x: 40, y: y, width: width - 80, height: 2))
        }
        for x in stride(from: 80, to: width, by: 128) {
            context.fill(CGRect(x: x, y: 50, width: 2, height: height - 100))
        }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 100, y: 100, width: 320, height: 120))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 120, y: 260, width: 180, height: 44))
        context.setFillColor(NSColor.darkGray.cgColor)
        for y in stride(from: 360, to: 620, by: 42) {
            context.fill(CGRect(x: 120, y: y, width: 520, height: 16))
        }

        guard let cgImage = context.makeImage() else {
            throw NSError(domain: "ImageKidTests", code: 2)
        }
        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }

    private func makePhotoLikeImage(width: Int, height: Int) throws -> NSImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 255, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * bytesPerPixel
                let xf = Double(x) / Double(max(width - 1, 1))
                let yf = Double(y) / Double(max(height - 1, 1))
                let wave = (sin(xf * .pi * 4) + cos(yf * .pi * 3)) * 0.5
                let r = UInt8(min(max((xf * 180) + 42 + wave * 18, 0), 255))
                let g = UInt8(min(max((yf * 170) + 35 - wave * 12, 0), 255))
                let b = UInt8(min(max(((1 - xf) * 110) + (yf * 85) + 48 + wave * 16, 0), 255))
                data[index] = r
                data[index + 1] = g
                data[index + 2] = b
                data[index + 3] = 255
            }
        }

        guard
            let context = CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let cgImage = context.makeImage()
        else {
            throw NSError(domain: "ImageKidTests", code: 4)
        }
        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }

    private func temporaryImageURL(for image: NSImage) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageKidTest-\(UUID().uuidString).png")
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "ImageKidTests", code: 3)
        }
        try data.write(to: url)
        return url
    }
}
