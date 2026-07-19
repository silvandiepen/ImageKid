import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Built-in background remover using Apple Vision's foreground instance mask.
/// Available on macOS 14+ and iOS 17+, on-device, with no model download. This
/// is the cross-platform equivalent of the app's "Built-in" engine.
public struct VisionBackgroundRemover: BackgroundRemover {
    public init() {}

    public func removeBackground(
        from image: CGImage,
        progress: InferenceProgressHandler?
    ) async throws -> CGImage {
        progress?(InferenceProgress(detail: "Finding the subject", fraction: nil))

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else {
            throw InferenceError.noForegroundFound
        }

        let maskedBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )

        let output = CIImage(cvPixelBuffer: maskedBuffer)
        let context = CIContext(options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull()
        ])
        guard let result = context.createCGImage(output, from: output.extent) else {
            throw InferenceError.outputDecodingFailed
        }

        progress?(InferenceProgress(detail: "Done", fraction: 1))
        return result
    }
}
