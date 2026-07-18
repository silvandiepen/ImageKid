import CoreGraphics
import CoreML
import CoreVideo
import Foundation

/// Configuration describing the converted Real-ESRGAN Core ML model.
///
/// These values MUST match what the conversion script produced. See
/// `tools/coreml-conversion/convert_realesrgan.py`, which writes an image input
/// and image output with these feature names and a native 4x scale.
public struct CoreMLUpscalerConfiguration: Sendable {
    /// The model's image input feature name.
    public var inputFeatureName: String
    /// The model's image output feature name.
    public var outputFeatureName: String
    /// The model's fixed upscale factor (Real-ESRGAN x4plus is 4).
    public var nativeScale: Int
    /// Core (non-overlap) tile edge in source pixels.
    public var tileSize: Int
    /// Overlap in source pixels added around each tile to hide seams.
    public var tileOverlap: Int
    /// If the model has a fixed input size, set it here and each tile is resized
    /// to it before inference. Leave `nil` for a flexible-shape model (preferred),
    /// which is fed each tile at its native pixel size.
    public var fixedInputSize: CGSize?

    public init(
        inputFeatureName: String = "input",
        outputFeatureName: String = "output",
        nativeScale: Int = 4,
        tileSize: Int = 256,
        tileOverlap: Int = 16,
        fixedInputSize: CGSize? = nil
    ) {
        self.inputFeatureName = inputFeatureName
        self.outputFeatureName = outputFeatureName
        self.nativeScale = nativeScale
        self.tileSize = tileSize
        self.tileOverlap = tileOverlap
        self.fixedInputSize = fixedInputSize
    }
}

/// Real-ESRGAN upscaler running entirely on-device through Core ML.
///
/// This is the cross-platform, App-Store-compatible replacement for the macOS
/// `ncnn-vulkan` subprocess: same model weights, in-process inference, no
/// downloaded executable. Large images are split into overlapped tiles so the
/// model only ever sees a bounded input.
public actor CoreMLUpscaler: ImageUpscaler {
    private let modelProvider: ModelProvider
    private let configuration: CoreMLUpscalerConfiguration
    private var cachedModel: MLModel?

    public init(modelProvider: ModelProvider, configuration: CoreMLUpscalerConfiguration = .init()) {
        self.modelProvider = modelProvider
        self.configuration = configuration
    }

    public func upscale(
        _ image: CGImage,
        to targetSize: CGSize,
        progress: InferenceProgressHandler?
    ) async throws -> CGImage {
        progress?(InferenceProgress(detail: "Preparing the model", fraction: nil))
        let model = try await loadModel()

        let scale = configuration.nativeScale
        let outputWidth = image.width * scale
        let outputHeight = image.height * scale

        let tiles = TilePlanner.plan(
            sourceWidth: image.width,
            sourceHeight: image.height,
            tileSize: configuration.tileSize,
            overlap: configuration.tileOverlap
        )

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: ImageConversion.sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw InferenceError.outputDecodingFailed
        }

        context.interpolationQuality = .high

        for (index, tile) in tiles.enumerated() {
            guard let readImage = ImageConversion.crop(image, to: tile.readRect) else { continue }
            let upscaledTile = try runModel(model, on: readImage)

            // Crop the core region out of the upscaled tile. `cropping(to:)` uses
            // top-left image coordinates, matching `coreOffsetInRead`.
            let coreInRead = tile.coreOffsetInRead
            let sourceSubRect = CGRect(
                x: coreInRead.minX * CGFloat(scale),
                y: coreInRead.minY * CGFloat(scale),
                width: coreInRead.width * CGFloat(scale),
                height: coreInRead.height * CGFloat(scale)
            ).integral

            let coreImage = ImageConversion.crop(upscaledTile, to: sourceSubRect) ?? upscaledTile
            // The context is not flipped, so `draw` renders upright and the
            // destination y is measured from the bottom.
            let destination = CGRect(
                x: tile.coreRect.minX * CGFloat(scale),
                y: CGFloat(outputHeight) - tile.coreRect.maxY * CGFloat(scale),
                width: tile.coreRect.width * CGFloat(scale),
                height: tile.coreRect.height * CGFloat(scale)
            )
            context.draw(coreImage, in: destination)

            let fraction = Double(index + 1) / Double(tiles.count)
            progress?(InferenceProgress(detail: "Upscaling \(Int((fraction * 100).rounded()))%", fraction: fraction))
        }

        guard let native = context.makeImage() else { throw InferenceError.outputDecodingFailed }

        // Real-ESRGAN produces a fixed 4x result; resize to the exact target.
        let targetWidth = Int(targetSize.width.rounded())
        let targetHeight = Int(targetSize.height.rounded())
        if native.width == targetWidth && native.height == targetHeight {
            return native
        }
        guard let resized = ImageConversion.resize(native, width: targetWidth, height: targetHeight) else {
            return native
        }
        return resized
    }

    private func loadModel() async throws -> MLModel {
        if let cachedModel { return cachedModel }
        let model = try await modelProvider.loadModel()
        cachedModel = model
        return model
    }

    private func runModel(_ model: MLModel, on tile: CGImage) throws -> CGImage {
        let inputWidth: Int
        let inputHeight: Int
        let modelInput: CGImage
        if let fixed = configuration.fixedInputSize {
            inputWidth = Int(fixed.width)
            inputHeight = Int(fixed.height)
            modelInput = ImageConversion.resize(tile, width: inputWidth, height: inputHeight) ?? tile
        } else {
            inputWidth = tile.width
            inputHeight = tile.height
            modelInput = tile
        }

        guard let buffer = ImageConversion.makeBGRAPixelBuffer(
            from: modelInput,
            width: inputWidth,
            height: inputHeight
        ) else {
            throw InferenceError.inputPreparationFailed
        }

        let provider = try MLDictionaryFeatureProvider(
            dictionary: [configuration.inputFeatureName: MLFeatureValue(pixelBuffer: buffer)]
        )
        let result = try model.prediction(from: provider)

        guard
            let feature = result.featureValue(for: configuration.outputFeatureName),
            let outputBuffer = feature.imageBufferValue
        else {
            throw InferenceError.outputMissing
        }

        guard var upscaled = ImageConversion.makeCGImage(from: outputBuffer) else {
            throw InferenceError.outputDecodingFailed
        }

        // A fixed-size model returns a fixed output; restore native tile scale.
        if configuration.fixedInputSize != nil {
            let expectedWidth = tile.width * configuration.nativeScale
            let expectedHeight = tile.height * configuration.nativeScale
            if upscaled.width != expectedWidth || upscaled.height != expectedHeight,
               let restored = ImageConversion.resize(upscaled, width: expectedWidth, height: expectedHeight) {
                upscaled = restored
            }
        }
        return upscaled
    }
}
