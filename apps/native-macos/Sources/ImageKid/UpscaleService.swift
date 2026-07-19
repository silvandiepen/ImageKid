import AppKit
import CoreImage
import Foundation
import ImageIO
import ImageKidInference
import UniformTypeIdentifiers

private final class UpscaleResultBox: @unchecked Sendable {
    var result: Result<CGImage, Error>?
}

enum ImageUpscaleService {
    /// Best Quality is the downloadable Core ML Real-ESRGAN model (no ncnn binary).
    static var isBestQualityRuntimeAvailable: Bool {
        CoreMLModel.realESRGAN.isDownloaded
    }

    static func upscale(
        _ image: NSImage,
        to targetSize: CGSize,
        contentMode: UpscaleContentMode,
        progress: (@Sendable (UpscaleProgressUpdate) -> Void)? = nil
    ) throws -> NSImage {
        let resolvedContentMode = resolvedContentMode(for: image, requestedMode: contentMode)

        if resolvedContentMode == .textAndUI {
            progress?(UpscaleProgressUpdate(detail: "Keeping sharp bits sharp", fraction: nil))
            return preserveTextUpscale(image, to: targetSize)
        }

        guard isBestQualityRuntimeAvailable else {
            throw UpscaleError.runtimeMissing
        }
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw UpscaleError.outputMissing
        }

        progress?(UpscaleProgressUpdate(detail: "Enlarging with Real-ESRGAN", fraction: nil))
        let upscaled = try coreMLUpscale(source, to: targetSize, progress: progress)
        return NSImage(cgImage: upscaled, size: targetSize)
    }

    /// Runs the on-device Core ML Real-ESRGAN upscaler. The service API is
    /// synchronous (callers run it off the main thread), so we bridge the async
    /// engine with a semaphore — the same blocking contract the old ncnn
    /// subprocess had.
    private static func coreMLUpscale(
        _ image: CGImage,
        to targetSize: CGSize,
        progress: (@Sendable (UpscaleProgressUpdate) -> Void)?
    ) throws -> CGImage {
        let provider = PackageModelProvider(packageURL: CoreMLModel.realESRGAN.localPackageURL)
        // Fixed 256×256 input matches the reliable conversion path (tools/coreml-conversion).
        let upscaler = CoreMLUpscaler(
            modelProvider: provider,
            configuration: CoreMLUpscalerConfiguration(fixedInputSize: CGSize(width: 256, height: 256))
        )

        let semaphore = DispatchSemaphore(value: 0)
        let box = UpscaleResultBox()
        Task.detached {
            do {
                box.result = .success(try await upscaler.upscale(image, to: targetSize, progress: { update in
                    progress?(UpscaleProgressUpdate(detail: update.detail, fraction: update.fraction))
                }))
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let result = box.result else { throw UpscaleError.outputMissing }
        return try result.get()
    }

    static func resolvedContentMode(for image: NSImage, requestedMode: UpscaleContentMode) -> UpscaleContentMode {
        guard requestedMode == .automatic else { return requestedMode }
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .textAndUI
        }
        return looksLikeScreenshotOrUI(source) ? .textAndUI : .photoArtwork
    }

    static func imageWithExactPixelSize(_ image: NSImage, size: CGSize) -> NSImage {
        if image.pixelSize == size {
            return image
        }
        return resize(image, to: size)
    }

    private static func looksLikeScreenshotOrUI(_ source: CGImage) -> Bool {
        let sampleSize = CGSize(width: 96, height: 96)
        guard let bitmap = sampledBitmap(from: source, size: sampleSize) else {
            return true
        }

        var uniqueBuckets = Set<Int>()
        var strongAxisEdges = 0
        var softEdges = 0
        var alphaPixels = 0
        var previousRow: [(r: Int, g: Int, b: Int, a: Int)] = []

        for y in 0..<bitmap.height {
            var previousPixel: (r: Int, g: Int, b: Int, a: Int)?
            var currentRow: [(r: Int, g: Int, b: Int, a: Int)] = []

            for x in 0..<bitmap.width {
                let pixel = bitmap.pixel(x: x, y: y)
                currentRow.append(pixel)
                if pixel.a < 245 { alphaPixels += 1 }

                uniqueBuckets.insert((pixel.r / 24) << 16 | (pixel.g / 24) << 8 | (pixel.b / 24))

                if let previousPixel {
                    let delta = colorDelta(pixel, previousPixel)
                    if delta > 78 { strongAxisEdges += 1 }
                    if delta > 18 && delta <= 78 { softEdges += 1 }
                }

                if y > 0 {
                    let delta = colorDelta(pixel, previousRow[x])
                    if delta > 78 { strongAxisEdges += 1 }
                    if delta > 18 && delta <= 78 { softEdges += 1 }
                }

                previousPixel = pixel
            }

            previousRow = currentRow
        }

        let samplePixels = max(bitmap.width * bitmap.height, 1)
        let edgeRatio = Double(strongAxisEdges) / Double(samplePixels * 2)
        let softEdgeRatio = Double(softEdges) / Double(samplePixels * 2)
        let colorRatio = Double(uniqueBuckets.count) / Double(samplePixels)
        let alphaRatio = Double(alphaPixels) / Double(samplePixels)

        if alphaRatio > 0.02 { return true }
        if uniqueBuckets.count > 760 && edgeRatio > 0.24 { return false }
        if colorRatio > 0.16 && softEdgeRatio > 0.18 { return false }
        if uniqueBuckets.count < 360 && edgeRatio > 0.08 { return true }
        if edgeRatio > 0.14 && softEdgeRatio < 0.22 { return true }
        if colorRatio < 0.07 && edgeRatio > 0.045 { return true }
        return false
    }

    private static func sampledBitmap(from source: CGImage, size: CGSize) -> SampledBitmap? {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

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
            )
        else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return SampledBitmap(width: width, height: height, data: data)
    }

    private static func colorDelta(
        _ lhs: (r: Int, g: Int, b: Int, a: Int),
        _ rhs: (r: Int, g: Int, b: Int, a: Int)
    ) -> Int {
        abs(lhs.r - rhs.r) + abs(lhs.g - rhs.g) + abs(lhs.b - rhs.b)
    }

    private static func preserveTextUpscale(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        guard
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let scaled = lanczosScale(source, to: targetSize)
        else {
            return sharpen(resize(image, to: targetSize))
        }

        let sharpened = applyTextUISharpening(scaled, targetSize: targetSize)
        guard shouldBlendNearestDetail(source: source, targetSize: targetSize) else {
            return sharpened
        }

        return blendNearestDetail(source: source, base: sharpened, targetSize: targetSize)
    }

    private static func preservePhotoUpscale(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        guard
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let scaled = lanczosScale(source, to: targetSize)
        else {
            return resize(image, to: targetSize)
        }

        return applyPhotoSharpening(scaled, targetSize: targetSize)
    }

    private static func resize(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        guard
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let colorSpace = source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let output = context.makeImage() else { return image }
        return NSImage(cgImage: output, size: CGSize(width: width, height: height))
    }

    private static func shouldBlendNearestDetail(source: CGImage, targetSize: CGSize) -> Bool {
        let widthScale = targetSize.width / CGFloat(max(source.width, 1))
        let heightScale = targetSize.height / CGFloat(max(source.height, 1))
        guard abs(widthScale - heightScale) < 0.01 else { return false }
        let roundedScale = widthScale.rounded()
        return roundedScale >= 2 && roundedScale <= 4 && abs(widthScale - roundedScale) < 0.02
    }

    private static func blendNearestDetail(source: CGImage, base: NSImage, targetSize: CGSize) -> NSImage {
        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        guard
            let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let colorSpace = source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return base
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(baseCG, in: rect)
        context.setAlpha(0.24)
        context.interpolationQuality = .none
        context.draw(source, in: rect)

        guard let output = context.makeImage() else { return base }
        return NSImage(cgImage: output, size: CGSize(width: width, height: height))
    }

    private static func lanczosScale(_ source: CGImage, to targetSize: CGSize) -> CIImage? {
        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        let sourceWidth = max(source.width, 1)
        let sourceHeight = max(source.height, 1)
        let scale = max(CGFloat(width) / CGFloat(sourceWidth), CGFloat(height) / CGFloat(sourceHeight))

        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        filter.setValue(CIImage(cgImage: source), forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1, forKey: kCIInputAspectRatioKey)

        guard let output = filter.outputImage else { return nil }
        return output.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func applyTextUISharpening(_ image: CIImage, targetSize: CGSize) -> NSImage {
        var output = image

        if let unsharpMask = CIFilter(name: "CIUnsharpMask") {
            unsharpMask.setValue(output, forKey: kCIInputImageKey)
            unsharpMask.setValue(0.54, forKey: kCIInputRadiusKey)
            unsharpMask.setValue(0.34, forKey: kCIInputIntensityKey)
            output = unsharpMask.outputImage ?? output
        }

        if let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(output, forKey: kCIInputImageKey)
            sharpen.setValue(0.08, forKey: kCIInputSharpnessKey)
            output = sharpen.outputImage ?? output
        }

        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        let exactExtent = CGRect(x: 0, y: 0, width: width, height: height)

        guard let cgImage = ciContext.createCGImage(output.cropped(to: exactExtent), from: exactExtent) else {
            return NSImage(size: CGSize(width: width, height: height))
        }

        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }

    private static func applyPhotoSharpening(_ image: CIImage, targetSize: CGSize) -> NSImage {
        var output = image

        if let unsharpMask = CIFilter(name: "CIUnsharpMask") {
            unsharpMask.setValue(output, forKey: kCIInputImageKey)
            unsharpMask.setValue(1.1, forKey: kCIInputRadiusKey)
            unsharpMask.setValue(0.18, forKey: kCIInputIntensityKey)
            output = unsharpMask.outputImage ?? output
        }

        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        let exactExtent = CGRect(x: 0, y: 0, width: width, height: height)

        guard let cgImage = ciContext.createCGImage(output.cropped(to: exactExtent), from: exactExtent) else {
            return NSImage(size: CGSize(width: width, height: height))
        }

        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }

    private static func sharpen(_ image: NSImage) -> NSImage {
        guard
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let filter = CIFilter(name: "CISharpenLuminance")
        else {
            return image
        }

        let input = CIImage(cgImage: source)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0.16, forKey: kCIInputSharpnessKey)

        guard
            let output = filter.outputImage,
            let cgImage = ciContext.createCGImage(output, from: output.extent)
        else {
            return image
        }

        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }

    private static let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: true
    ])
}

private struct SampledBitmap {
    let width: Int
    let height: Int
    let data: [UInt8]

    func pixel(x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let index = (y * width + x) * 4
        return (
            r: Int(data[index]),
            g: Int(data[index + 1]),
            b: Int(data[index + 2]),
            a: Int(data[index + 3])
        )
    }
}

struct UpscaleProgressUpdate: Sendable {
    let detail: String
    let fraction: Double?
}

private enum UpscaleError: LocalizedError {
    case runtimeMissing
    case inputEncodingFailed
    case outputMissing
    case commandFailed(String)
    case corruptOutput(CGSize)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            "Best Quality is not ready yet. Turn it on in Settings > Upscale."
        case .inputEncodingFailed:
            "ImageKid could not get this picture ready for stretching."
        case .outputMissing:
            "The stretch finished without giving ImageKid an image back."
        case .commandFailed(let message):
            "Best Quality got stuck: \(message)"
        case .corruptOutput(let size):
            "Best Quality made a messy \(Int(size.width)) × \(Int(size.height)) px result. Try a smaller stretch or restart ImageKid before running it again."
        case .installFailed(let message):
            "Best Quality setup failed: \(message)"
        }
    }
}

private extension NSImage {
    var pixelSize: CGSize {
        if let representation = representations.first {
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return size
    }
}
