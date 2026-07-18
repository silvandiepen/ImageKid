import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

enum BackgroundRemovalService {
    static var isBestQualityRuntimeAvailable: Bool {
        managedRembgExecutableURL() != nil
    }

    static func removeBackground(from source: CGImage, engine: BackgroundRemovalEngine) throws -> CGImage {
        switch engine {
        case .builtIn:
            return try removeWithVision(from: source)
        case .bestQuality:
            return try removeWithRembg(from: source)
        }
    }

    private static func removeWithVision(from source: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: source, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else {
            throw BackgroundRemovalError.noForegroundFound
        }

        let outputBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )
        let output = CIImage(cvPixelBuffer: outputBuffer)

        guard
            let result = CIContext(options: [
                .workingColorSpace: NSNull(),
                .outputColorSpace: NSNull()
            ]).createCGImage(output, from: output.extent)
        else {
            throw BackgroundRemovalError.renderFailed
        }

        return result
    }

    private static func removeWithRembg(from source: CGImage) throws -> CGImage {
        guard let rembgURL = managedRembgExecutableURL() else {
            throw BackgroundRemovalError.bestQualityRuntimeMissing
        }

        let modelURL = BackgroundRemovalModelConfiguration.modelsDirectory
            .appendingPathComponent(BackgroundRemovalModelConfiguration.modelFileName)
        guard (try? BackgroundRemovalAssetVerifier.validateModel(at: modelURL)) != nil else {
            throw BackgroundRemovalError.bestQualityModelMissing
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageKid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("input.png")
        let outputURL = directory.appendingPathComponent("output.png")
        try writePNG(source, to: inputURL)

        let process = Process()
        process.executableURL = rembgURL
        process.arguments = [
            "i",
            "-m",
            BackgroundRemovalModelConfiguration.modelName,
            inputURL.path,
            outputURL.path
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "U2NET_HOME": BackgroundRemovalModelConfiguration.modelsDirectory.path
        ]) { _, new in new }

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BackgroundRemovalError.bestQualityFailed(message ?? "The background peeler stopped with status \(process.terminationStatus).")
        }

        guard let result = NSImage(contentsOf: outputURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw BackgroundRemovalError.renderFailed
        }
        return result
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw BackgroundRemovalError.renderFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw BackgroundRemovalError.renderFailed
        }
    }

    private static func managedRembgExecutableURL() -> URL? {
        if BackgroundRemovalAssetVerifier.isManagedRuntimeInstalled {
            return BackgroundRemovalModelConfiguration.managedRembgExecutableURL
        }
        return nil
    }
}

enum BackgroundRemovalError: LocalizedError {
    case noForegroundFound
    case renderFailed
    case bestQualityModelMissing
    case bestQualityRuntimeMissing
    case bestQualityFailed(String)

    var errorDescription: String? {
        switch self {
        case .noForegroundFound:
            "ImageKid could not find a clear foreground subject in this image."
        case .renderFailed:
            "ImageKid could not render the background-removed image."
        case .bestQualityModelMissing:
            "Turn on the Best Quality add-on in Settings before using this option."
        case .bestQualityRuntimeMissing:
            "Best Quality is not ready yet. Turn it on in Settings, then try again."
        case .bestQualityFailed(let message):
            "Best Quality got stuck while peeling the background: \(message)"
        }
    }
}
