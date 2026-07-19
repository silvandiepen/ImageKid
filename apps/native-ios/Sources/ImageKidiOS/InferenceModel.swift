import CoreGraphics
import Foundation
import ImageKidInference
import UIKit

/// Drives the ImageKidInference engines for the iOS UI. All published state is
/// main-actor isolated; the heavy model work runs inside the engine actors.
@MainActor
final class InferenceModel: ObservableObject {
    @Published var sourceImage: UIImage?
    @Published var resultImage: UIImage?
    @Published var resultShareURL: URL?
    @Published var statusText: String?
    @Published var progress: Double?
    @Published var isBusy = false
    @Published var errorMessage: String?

    // Built-in engines: always available, no model download.
    private let visionRemover = VisionBackgroundRemover()

    // Best Quality engines: available only when the converted models are present
    // in the app bundle (drag the .mlpackage files into the target — Xcode
    // compiles them to .mlmodelc). See tools/coreml-conversion.
    private let isnetProvider = BundledModelProvider(name: "ISNet", bundle: .main)
    private let realESRGANProvider = BundledModelProvider(name: "RealESRGAN", bundle: .main)
    private lazy var isnetRemover = CoreMLBackgroundRemover(modelProvider: isnetProvider)
    private lazy var realESRGANUpscaler = CoreMLUpscaler(modelProvider: realESRGANProvider)

    var bestQualityBackgroundAvailable: Bool { isnetProvider.isAvailable }
    var bestQualityUpscaleAvailable: Bool { realESRGANProvider.isAvailable }

    /// The image currently shown and acted on: the latest result, or the source.
    var workingImage: UIImage? { resultImage ?? sourceImage }

    /// Applies a crop expressed as a normalised rectangle (top-left origin) to
    /// the current working image, making the result the new working image.
    func applyCrop(normalizedRect: CGRect) {
        guard let source = workingImage?.normalizedCGImage() else { return }
        let pixelRect = CGRect(
            x: normalizedRect.minX * CGFloat(source.width),
            y: normalizedRect.minY * CGFloat(source.height),
            width: normalizedRect.width * CGFloat(source.width),
            height: normalizedRect.height * CGFloat(source.height)
        ).integral
        guard let cropped = source.cropping(to: pixelRect) else { return }
        resultImage = UIImage(cgImage: cropped)
        resultShareURL = ShareFile.makePNG(from: cropped)
        statusText = "Cropped"
    }

    /// Replaces the working image with an already-rendered edit (e.g. flattened
    /// annotations).
    func applyEditedImage(_ image: CGImage, status: String) {
        resultImage = UIImage(cgImage: image)
        resultShareURL = ShareFile.makePNG(from: image)
        statusText = status
    }

    /// Resizes the working image to an exact pixel size.
    func applyResize(width: Int, height: Int) {
        guard let source = workingImage?.normalizedCGImage() else { return }
        guard let resized = source.resizedExact(width: width, height: height) else { return }
        resultImage = UIImage(cgImage: resized)
        resultShareURL = ShareFile.makePNG(from: resized)
        statusText = "Resized to \(width)×\(height)"
    }

    func setSource(_ image: UIImage) {
        sourceImage = image
        resultImage = nil
        resultShareURL = nil
        errorMessage = nil
        statusText = nil
        progress = nil
    }

    func removeBackground(bestQuality: Bool) {
        run { [self] progress in
            guard let source = sourceImage?.normalizedCGImage() else {
                throw InferenceError.inputPreparationFailed
            }
            if bestQuality {
                return try await isnetRemover.removeBackground(from: source, progress: progress)
            }
            return try await visionRemover.removeBackground(from: source, progress: progress)
        }
    }

    func upscale(scale: CGFloat, bestQuality: Bool) {
        run { [self] progress in
            guard let source = sourceImage?.normalizedCGImage() else {
                throw InferenceError.inputPreparationFailed
            }
            let target = CGSize(
                width: CGFloat(source.width) * scale,
                height: CGFloat(source.height) * scale
            )
            if bestQuality {
                return try await realESRGANUpscaler.upscale(source, to: target, progress: progress)
            }
            return try await CoreImageUpscaler(sharpening: .photoArtwork)
                .upscale(source, to: target, progress: progress)
        }
    }

    /// Runs an inference operation, wiring progress and results back to the UI.
    private func run(_ work: @escaping (@escaping InferenceProgressHandler) async throws -> CGImage) {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        resultImage = nil
        resultShareURL = nil
        progress = nil
        statusText = "Working…"

        let handler: InferenceProgressHandler = { [weak self] update in
            Task { @MainActor in
                self?.statusText = update.detail
                self?.progress = update.fraction
            }
        }

        Task {
            do {
                let output = try await work(handler)
                resultImage = UIImage(cgImage: output)
                resultShareURL = ShareFile.makePNG(from: output)
                statusText = "Done"
            } catch {
                errorMessage = error.localizedDescription
                statusText = nil
            }
            progress = nil
            isBusy = false
        }
    }
}
