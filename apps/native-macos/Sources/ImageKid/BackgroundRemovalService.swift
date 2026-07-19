import AppKit
import CoreImage
import CoreML
import ImageIO
import ImageKidInference
import UniformTypeIdentifiers
import Vision

enum BackgroundRemovalService {
    /// Best Quality is the downloadable Core ML BiRefNet model (no Python runtime).
    static var isBestQualityRuntimeAvailable: Bool {
        CoreMLModel.birefnet.isDownloaded
    }

    static func removeBackground(from source: CGImage, engine: BackgroundRemovalEngine) async throws -> CGImage {
        switch engine {
        case .builtIn:
            return try removeWithVision(from: source)
        case .bestQuality:
            return try await removeWithCoreML(from: source)
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

    /// BiRefNet must run in fp32 on the CPU (fp16 on the ANE/GPU overflows on its
    /// Swin backbone and produces NaNs). Matches the iOS configuration.
    private static func removeWithCoreML(from source: CGImage) async throws -> CGImage {
        guard CoreMLModel.birefnet.isDownloaded else {
            throw BackgroundRemovalError.bestQualityModelMissing
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let provider = PackageModelProvider(
            packageURL: CoreMLModel.birefnet.localPackageURL,
            configuration: configuration
        )
        let remover = CoreMLBackgroundRemover(modelProvider: provider)
        return try await remover.removeBackground(from: source, progress: nil)
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
