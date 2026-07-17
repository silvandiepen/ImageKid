import AppKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum UpscaleRuntimeConfiguration {
    static let runtimeURL = URL(string: "https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan/releases/download/v0.2.0/realesrgan-ncnn-vulkan-v0.2.0-macos.zip")!
    static let modelsURL = URL(string: "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-ubuntu.zip")!
    static let executableName = "realesrgan-ncnn-vulkan"
    static let modelName = "realesrgan-x4plus"
    static let requiredModelFiles = [
        "realesrgan-x4plus.param",
        "realesrgan-x4plus.bin"
    ]

    static var runtimeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("ImageKid", isDirectory: true)
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("realesrgan", isDirectory: true)
    }

    static var executableURL: URL {
        runtimeDirectory.appendingPathComponent(executableName)
    }

    static var modelDirectoryURL: URL {
        runtimeDirectory.appendingPathComponent("models", isDirectory: true)
    }
}

@MainActor
final class UpscaleRuntimeManager: ObservableObject {
    @Published private(set) var isInstalling = false
    @Published private(set) var errorMessage: String?

    var isInstalled: Bool {
        ImageUpscaleService.isBestQualityRuntimeAvailable
    }

    var installedSizeLabel: String {
        guard
            let size = directorySize(at: UpscaleRuntimeConfiguration.runtimeDirectory)
        else {
            return "Not installed"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    func install() {
        guard !isInstalling else { return }
        isInstalling = true
        errorMessage = nil

        Task {
            do {
                let (runtimeArchiveURL, _) = try await URLSession.shared.download(from: UpscaleRuntimeConfiguration.runtimeURL)
                let (modelsArchiveURL, _) = try await URLSession.shared.download(from: UpscaleRuntimeConfiguration.modelsURL)
                try await Task.detached(priority: .userInitiated) {
                    try installUpscaleRuntime(from: runtimeArchiveURL, modelsArchiveURL: modelsArchiveURL)
                }.value
                objectWillChange.send()
            } catch {
                errorMessage = error.localizedDescription
            }

            isInstalling = false
        }
    }

    func remove() {
        do {
            if FileManager.default.fileExists(atPath: UpscaleRuntimeConfiguration.runtimeDirectory.path) {
                try FileManager.default.removeItem(at: UpscaleRuntimeConfiguration.runtimeDirectory)
            }
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum ImageUpscaleService {
    static var isBestQualityRuntimeAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: UpscaleRuntimeConfiguration.executableURL.path)
            && UpscaleRuntimeConfiguration.requiredModelFiles.allSatisfy {
                FileManager.default.fileExists(
                    atPath: UpscaleRuntimeConfiguration.modelDirectoryURL
                        .appendingPathComponent($0)
                        .path
                )
            }
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

        let modelScale = 4

        progress?(UpscaleProgressUpdate(detail: "Measuring every pixel", fraction: nil))
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageKidUpscale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let inputURL = workingDirectory.appendingPathComponent("input.png")
        try writePNG(image, to: inputURL)

        let runConfigurations = [
            RealESRGANRunConfiguration(tileSize: 0, threadPlan: "1:1:1"),
            RealESRGANRunConfiguration(tileSize: 512, threadPlan: "1:1:1"),
            RealESRGANRunConfiguration(tileSize: 256, threadPlan: "1:1:1"),
            RealESRGANRunConfiguration(tileSize: 128, threadPlan: "1:1:1")
        ]
        var lastUpscaled: NSImage?

        for configuration in runConfigurations {
            let outputURL = workingDirectory
                .appendingPathComponent("output-\(configuration.outputSuffix).png")
            try runUpscaler(
                inputURL: inputURL,
                outputURL: outputURL,
                scale: modelScale,
                configuration: configuration,
                progress: progress
            )

            guard let upscaled = NSImage(contentsOf: outputURL) else {
                throw UpscaleError.outputMissing
            }

            progress?(UpscaleProgressUpdate(detail: "Checking the stretch", fraction: nil))
            lastUpscaled = upscaled
            if !hasLikelyTileCorruption(upscaled, preferredTileSize: configuration.tileSize) {
                progress?(UpscaleProgressUpdate(detail: "Tucking in the edges", fraction: nil))
                let exactImage = upscaled.pixelSize == targetSize ? upscaled : resize(upscaled, to: targetSize)
                return exactImage
            }

            progress?(UpscaleProgressUpdate(detail: "That stretch looked weird; trying again", fraction: nil))
        }

        if let lastUpscaled {
            let exactImage = lastUpscaled.pixelSize == targetSize ? lastUpscaled : resize(lastUpscaled, to: targetSize)
            throw UpscaleError.corruptOutput(exactImage.pixelSize)
        }
        throw UpscaleError.outputMissing
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

    private static func runUpscaler(
        inputURL: URL,
        outputURL: URL,
        scale: Int,
        configuration: RealESRGANRunConfiguration,
        progress: (@Sendable (UpscaleProgressUpdate) -> Void)?
    ) throws {
        progress?(UpscaleProgressUpdate(detail: configuration.progressLabel, fraction: nil))

        let process = Process()
        process.executableURL = UpscaleRuntimeConfiguration.executableURL
        process.currentDirectoryURL = UpscaleRuntimeConfiguration.runtimeDirectory
        process.arguments = [
            "-i", inputURL.path,
            "-o", outputURL.path,
            "-n", UpscaleRuntimeConfiguration.modelName,
            "-s", String(scale),
            "-m", UpscaleRuntimeConfiguration.modelDirectoryURL.path,
            "-f", "png",
            "-t", String(configuration.tileSize),
            "-j", configuration.threadPlan
        ]

        let outputPipe = Pipe()
        let outputLock = NSLock()
        var outputData = Data()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputLock.lock()
            outputData.append(data)
            outputLock.unlock()

            guard
                let text = String(data: data, encoding: .utf8),
                let percentage = progressPercentage(in: text)
            else {
                return
            }
            progress?(UpscaleProgressUpdate(
                detail: "\(configuration.progressLabel) \(Int(percentage.rounded()))%",
                fraction: percentage / 100
            ))
        }

        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            outputLock.lock()
            let data = outputData
            outputLock.unlock()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpscaleError.commandFailed(message ?? "The image stretcher stopped with status \(process.terminationStatus).")
        }
    }

    private static func progressPercentage(in text: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*%"#
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Double(text[range])
    }

    private static func hasLikelyTileCorruption(_ image: NSImage, preferredTileSize: Int) -> Bool {
        guard
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let bitmap = sampledBitmap(from: source, size: CGSize(width: 192, height: 192))
        else {
            return false
        }

        let tileSizes = ([preferredTileSize, 512, 256, 128, 64, 32])
            .filter { $0 > 0 && source.width >= $0 * 3 && source.height >= $0 * 3 }
        guard !tileSizes.isEmpty else { return false }

        return tileSizes.contains { tileSize in
            hasLikelyTileCorruption(source: source, bitmap: bitmap, tileSize: tileSize)
        }
    }

    private static func hasLikelyTileCorruption(source: CGImage, bitmap: SampledBitmap, tileSize: Int) -> Bool {
        var allDelta = 0
        var allCount = 0
        var seamDelta = 0
        var seamCount = 0
        let sampledTile = max(8, Int((CGFloat(tileSize) / CGFloat(max(source.width, source.height))) * 192))

        for y in 0..<bitmap.height {
            for x in 1..<bitmap.width {
                let delta = colorDelta(bitmap.pixel(x: x, y: y), bitmap.pixel(x: x - 1, y: y))
                allDelta += delta
                allCount += 1
                if x % sampledTile == 0 {
                    seamDelta += delta
                    seamCount += 1
                }
            }
        }

        for y in 1..<bitmap.height {
            for x in 0..<bitmap.width {
                let delta = colorDelta(bitmap.pixel(x: x, y: y), bitmap.pixel(x: x, y: y - 1))
                allDelta += delta
                allCount += 1
                if y % sampledTile == 0 {
                    seamDelta += delta
                    seamCount += 1
                }
            }
        }

        guard allCount > 0, seamCount > 0 else { return false }
        let averageDelta = Double(allDelta) / Double(allCount)
        let averageSeamDelta = Double(seamDelta) / Double(seamCount)
        return averageSeamDelta > max(55, averageDelta * 2.7)
    }

    private static func writePNG(_ image: NSImage, to url: URL) throws {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard
            let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw UpscaleError.inputEncodingFailed
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw UpscaleError.inputEncodingFailed
        }
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

private func installUpscaleRuntime(from archiveURL: URL, modelsArchiveURL: URL) throws {
    let fileManager = FileManager.default
    let runtimeDirectory = UpscaleRuntimeConfiguration.runtimeDirectory
    let parentDirectory = runtimeDirectory.deletingLastPathComponent()
    let extractionDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("ImageKidUpscaleRuntime-\(UUID().uuidString)", isDirectory: true)

    try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: extractionDirectory) }

    try runUnzip(archiveURL: archiveURL, destinationURL: extractionDirectory)

    let executableURL = try findExecutable(named: UpscaleRuntimeConfiguration.executableName, under: extractionDirectory)
    let extractedRoot = executableURL.deletingLastPathComponent()

    if fileManager.fileExists(atPath: runtimeDirectory.path) {
        try fileManager.removeItem(at: runtimeDirectory)
    }
    try fileManager.moveItem(at: extractedRoot, to: runtimeDirectory)

    let installedExecutable = UpscaleRuntimeConfiguration.executableURL
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedExecutable.path)

    try installUpscaleModels(from: modelsArchiveURL)
}

private func installUpscaleModels(from archiveURL: URL) throws {
    let fileManager = FileManager.default
    let extractionDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("ImageKidUpscaleModels-\(UUID().uuidString)", isDirectory: true)

    try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: extractionDirectory) }

    try runUnzip(archiveURL: archiveURL, destinationURL: extractionDirectory)
    let sourceModelDirectory = try findDirectory(named: "models", under: extractionDirectory)
    let targetModelDirectory = UpscaleRuntimeConfiguration.modelDirectoryURL

    if fileManager.fileExists(atPath: targetModelDirectory.path) {
        try fileManager.removeItem(at: targetModelDirectory)
    }
    try fileManager.copyItem(at: sourceModelDirectory, to: targetModelDirectory)

    let missingFiles = UpscaleRuntimeConfiguration.requiredModelFiles.filter {
        !fileManager.fileExists(atPath: targetModelDirectory.appendingPathComponent($0).path)
    }
    if !missingFiles.isEmpty {
        throw UpscaleError.installFailed("The detail pack was missing \(missingFiles.joined(separator: ", ")).")
    }
}

private func runUnzip(archiveURL: URL, destinationURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-q", archiveURL.path, "-d", destinationURL.path]

    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw UpscaleError.installFailed(message ?? "unzip exited with status \(process.terminationStatus).")
    }
}

private func findExecutable(named name: String, under root: URL) throws -> URL {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw UpscaleError.installFailed("The add-on could not be checked.")
    }

    for case let url as URL in enumerator where url.lastPathComponent == name {
        return url
    }

    throw UpscaleError.installFailed("The add-on was missing \(name).")
}

private func findDirectory(named name: String, under root: URL) throws -> URL {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw UpscaleError.installFailed("The detail pack could not be checked.")
    }

    for case let url as URL in enumerator where url.lastPathComponent == name {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            return url
        }
    }

    throw UpscaleError.installFailed("The detail pack was incomplete.")
}

private func directorySize(at url: URL) -> Int? {
    guard
        FileManager.default.fileExists(atPath: url.path),
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
    else {
        return nil
    }

    var size = 0
    for case let fileURL as URL in enumerator {
        size += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
    return size
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

private struct RealESRGANRunConfiguration {
    let tileSize: Int
    let threadPlan: String

    var outputSuffix: String {
        tileSize == 0 ? "untiled" : "tile-\(tileSize)"
    }

    var progressLabel: String {
        tileSize == 0 ? "Stretching it up carefully" : "Trying a lighter stretch"
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
