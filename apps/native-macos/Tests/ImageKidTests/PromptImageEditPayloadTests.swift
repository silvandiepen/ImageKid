import AppKit
import XCTest
@testable import ImageKid

@MainActor
final class PromptImageEditPayloadTests: XCTestCase {
    func testPayloadUsesFullRenderedImageWithoutSelection() throws {
        let session = ImageSession(sourceURL: nil, sourceImage: makeImage(width: 120, height: 80))

        let payload = try PromptImageEditPayloadBuilder.payload(for: session)
        let sourceSize = pixelSize(of: payload.sourceImage)

        XCTAssertEqual(payload.scope, .fullImage)
        XCTAssertEqual(pixelSize(of: payload.image), sourceSize)
    }

    func testPayloadUsesOnlySelectedCrop() throws {
        let session = ImageSession(sourceURL: nil, sourceImage: makeImage(width: 100, height: 60))
        session.selectionRect = CGRect(x: 0.2, y: 0.25, width: 0.5, height: 0.5)

        let payload = try PromptImageEditPayloadBuilder.payload(for: session)
        let sourceSize = pixelSize(of: payload.sourceImage)

        XCTAssertEqual(payload.scope, .selection(CGRect(x: 0.2, y: 0.25, width: 0.5, height: 0.5)))
        XCTAssertEqual(pixelSize(of: payload.image), CGSize(width: sourceSize.width * 0.5, height: sourceSize.height * 0.5))
    }

    func testPayloadIgnoresTinyInvalidSelection() throws {
        let session = ImageSession(sourceURL: nil, sourceImage: makeImage(width: 100, height: 60))
        session.selectionRect = CGRect(x: 0.2, y: 0.25, width: 0.001, height: 0.5)

        let payload = try PromptImageEditPayloadBuilder.payload(for: session)
        let sourceSize = pixelSize(of: payload.sourceImage)

        XCTAssertEqual(payload.scope, .fullImage)
        XCTAssertEqual(pixelSize(of: payload.image), sourceSize)
    }

    private func makeImage(width: Int, height: Int) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = CGSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: CGSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }

    private func pixelSize(of image: NSImage) -> CGSize {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .zero
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }
}
