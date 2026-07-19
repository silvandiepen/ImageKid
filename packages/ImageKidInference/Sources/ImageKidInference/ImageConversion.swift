import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

/// Cross-platform image helpers shared by the engines. Everything is expressed
/// in `CGImage` and `CVPixelBuffer` so the package never imports AppKit or
/// UIKit and works unchanged on macOS and iOS.
enum ImageConversion {
    /// A shared, GPU-backed Core Image context for encode/decode work.
    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Draws `image` into a freshly allocated 32BGRA `CVPixelBuffer` of the given
    /// size, scaling to fill. Suitable as a Core ML image input.
    static func makeBGRAPixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        makePixelBuffer(width: width, height: height, pixelFormat: kCVPixelFormatType_32BGRA) { context in
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Allocates a `CVPixelBuffer` and lets `draw` render into a `CGContext`
    /// backed by it. Returns `nil` if allocation or context creation fails.
    static func makePixelBuffer(
        width: Int,
        height: Int,
        pixelFormat: OSType,
        draw: (CGContext) -> Void
    ) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard
            let base = CVPixelBufferGetBaseAddress(pixelBuffer),
            let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            return nil
        }

        draw(context)
        return pixelBuffer
    }

    /// Renders a `CVPixelBuffer` back into a `CGImage`.
    static func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }

    /// Resizes `image` to an exact pixel size with high-quality interpolation.
    static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let safeWidth = max(1, width)
        let safeHeight = max(1, height)
        guard let context = CGContext(
            data: nil,
            width: safeWidth,
            height: safeHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: safeWidth, height: safeHeight))
        return context.makeImage()
    }

    /// Whether an image carries a (non-opaque) alpha channel.
    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            return true
        }
    }

    /// Re-applies `source`'s alpha channel (scaled to `upscaled`'s size) onto an
    /// upscaled RGB image. Upscalers (Real-ESRGAN especially) work on RGB only and
    /// drop transparency — without this, transparent regions come back as opaque
    /// black. Returns `upscaled` unchanged if the source is fully opaque.
    static func reapplyAlpha(from source: CGImage, onto upscaled: CGImage) -> CGImage {
        guard hasAlpha(source) else { return upscaled }
        let width = upscaled.width
        let height = upscaled.height
        let bytesPerRow = width * 4
        let count = height * bytesPerRow
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        // Source alpha, scaled to the upscaled size (premultiplied RGBA).
        var sourcePixels = [UInt8](repeating: 0, count: count)
        // The upscaled RGB, drawn opaque.
        var outputPixels = [UInt8](repeating: 0, count: count)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)

        guard
            let sourceContext = CGContext(
                data: &sourcePixels, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: sRGB, bitmapInfo: bitmapInfo
            ),
            let outputContext = CGContext(
                data: &outputPixels, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: sRGB, bitmapInfo: bitmapInfo
            )
        else {
            return upscaled
        }

        sourceContext.interpolationQuality = .high
        sourceContext.draw(source, in: rect)
        outputContext.interpolationQuality = .high
        outputContext.draw(upscaled, in: rect)

        // Replace the output's alpha with the scaled source alpha, keeping the RGB
        // premultiplied so it composites correctly.
        for index in stride(from: 0, to: count, by: 4) {
            let alpha = Int(sourcePixels[index + 3])
            outputPixels[index] = UInt8(Int(outputPixels[index]) * alpha / 255)
            outputPixels[index + 1] = UInt8(Int(outputPixels[index + 1]) * alpha / 255)
            outputPixels[index + 2] = UInt8(Int(outputPixels[index + 2]) * alpha / 255)
            outputPixels[index + 3] = UInt8(alpha)
        }

        return outputContext.makeImage() ?? upscaled
    }

    /// Crops a pixel rectangle out of `image`, clamped to the image bounds.
    static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = rect.intersection(bounds).integral
        guard !clamped.isEmpty else { return nil }
        return image.cropping(to: clamped)
    }
}
