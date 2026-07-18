import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation

/// Configuration describing the converted ISNet Core ML model.
///
/// Must match `tools/coreml-conversion/convert_isnet.py`. That script writes an
/// image input (with the ISNet normalisation baked in) and a single-channel
/// mask output.
public struct CoreMLBackgroundRemoverConfiguration: Sendable {
    public var inputFeatureName: String
    public var outputFeatureName: String
    /// The fixed input size the model expects (ISNet general-use is 1024x1024).
    public var inputSize: CGSize

    public init(
        inputFeatureName: String = "input",
        outputFeatureName: String = "output",
        inputSize: CGSize = CGSize(width: 1024, height: 1024)
    ) {
        self.inputFeatureName = inputFeatureName
        self.outputFeatureName = outputFeatureName
        self.inputSize = inputSize
    }
}

/// Best Quality background remover using the ISNet model through Core ML.
///
/// Cross-platform, in-process replacement for the macOS `rembg` Python
/// subprocess: same ISNet weights, no Python runtime, no downloaded executable.
/// The output alpha matches the Mac Best Quality engine, including the same
/// min-max mask normalisation `rembg` applies.
public actor CoreMLBackgroundRemover: BackgroundRemover {
    private let modelProvider: ModelProvider
    private let configuration: CoreMLBackgroundRemoverConfiguration
    private var cachedModel: MLModel?

    public init(
        modelProvider: ModelProvider,
        configuration: CoreMLBackgroundRemoverConfiguration = .init()
    ) {
        self.modelProvider = modelProvider
        self.configuration = configuration
    }

    public func removeBackground(
        from image: CGImage,
        progress: InferenceProgressHandler?
    ) async throws -> CGImage {
        progress?(InferenceProgress(detail: "Preparing the model", fraction: nil))
        let model = try await loadModel()

        let inputWidth = Int(configuration.inputSize.width)
        let inputHeight = Int(configuration.inputSize.height)
        guard let buffer = ImageConversion.makeBGRAPixelBuffer(
            from: image,
            width: inputWidth,
            height: inputHeight
        ) else {
            throw InferenceError.inputPreparationFailed
        }

        progress?(InferenceProgress(detail: "Finding the subject", fraction: nil))
        let provider = try MLDictionaryFeatureProvider(
            dictionary: [configuration.inputFeatureName: MLFeatureValue(pixelBuffer: buffer)]
        )
        let result = try model.prediction(from: provider)

        guard let feature = result.featureValue(for: configuration.outputFeatureName) else {
            throw InferenceError.outputMissing
        }

        let maskImage = try maskCIImage(from: feature)
        let composed = try compose(source: image, mask: maskImage)

        progress?(InferenceProgress(detail: "Done", fraction: 1))
        return composed
    }

    private func loadModel() async throws -> MLModel {
        if let cachedModel { return cachedModel }
        let model = try await modelProvider.loadModel()
        cachedModel = model
        return model
    }

    /// Turns the model's mask output (image or multi-array) into a `CIImage`.
    private func maskCIImage(from feature: MLFeatureValue) throws -> CIImage {
        if let buffer = feature.imageBufferValue {
            return CIImage(cvPixelBuffer: buffer)
        }
        if let array = feature.multiArrayValue, let cgMask = Self.grayscaleImage(from: array) {
            return CIImage(cgImage: cgMask)
        }
        throw InferenceError.outputMissing
    }

    /// Blends the full-resolution source against a transparent background using
    /// the mask as alpha. The mask is scaled to the source extent first.
    private func compose(source: CGImage, mask: CIImage) throws -> CGImage {
        let sourceImage = CIImage(cgImage: source)
        let sourceExtent = sourceImage.extent

        let maskExtent = mask.extent
        guard maskExtent.width > 0, maskExtent.height > 0 else {
            throw InferenceError.outputDecodingFailed
        }
        let scaledMask = mask.transformed(by: CGAffineTransform(
            scaleX: sourceExtent.width / maskExtent.width,
            y: sourceExtent.height / maskExtent.height
        ))

        guard let blend = CIFilter(name: "CIBlendWithMask") else {
            throw InferenceError.outputDecodingFailed
        }
        blend.setValue(sourceImage, forKey: kCIInputImageKey)
        blend.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blend.setValue(scaledMask, forKey: "inputMaskImage")

        guard
            let output = blend.outputImage,
            let result = ImageConversion.ciContext.createCGImage(output, from: sourceExtent)
        else {
            throw InferenceError.outputDecodingFailed
        }
        return result
    }

    /// Converts a single-channel `MLMultiArray` mask to an 8-bit grayscale image,
    /// applying the same per-image min-max normalisation `rembg` uses so the
    /// alpha matches the Mac Best Quality engine.
    static func grayscaleImage(from array: MLMultiArray) -> CGImage? {
        let shape = array.shape.map { $0.intValue }
        guard let (width, height) = maskDimensions(from: shape) else { return nil }
        let count = width * height
        guard count > 0, array.count >= count else { return nil }

        var values = [Float](repeating: 0, count: count)
        let offset = array.count - count // last HxW plane, robust to leading 1-dims
        switch array.dataType {
        case .float32:
            let pointer = array.dataPointer.assumingMemoryBound(to: Float.self)
            for index in 0..<count { values[index] = pointer[offset + index] }
        case .double:
            let pointer = array.dataPointer.assumingMemoryBound(to: Double.self)
            for index in 0..<count { values[index] = Float(pointer[offset + index]) }
        default:
            for index in 0..<count { values[index] = array[offset + index].floatValue }
        }

        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        for value in values {
            minimum = min(minimum, value)
            maximum = max(maximum, value)
        }
        let range = maximum - minimum
        var pixels = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            let normalized = range > 0 ? (values[index] - minimum) / range : 0
            pixels[index] = UInt8(max(0, min(255, (normalized * 255).rounded())))
        }

        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return nil
            }
            return context.makeImage()
        }
    }

    /// Extracts (width, height) from common mask shapes: [W,H]-last layouts such
    /// as [1,1,H,W], [1,H,W], or [H,W].
    static func maskDimensions(from shape: [Int]) -> (width: Int, height: Int)? {
        let trimmed = shape.filter { $0 > 1 }.suffix(2)
        if trimmed.count == 2 {
            let dims = Array(trimmed)
            return (width: dims[1], height: dims[0])
        }
        if let last = shape.last, shape.count >= 2 {
            let height = shape[shape.count - 2]
            return (width: last, height: height)
        }
        return nil
    }
}
