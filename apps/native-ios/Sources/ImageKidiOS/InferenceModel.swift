import CoreGraphics
import Foundation
import ImageKidInference
import UIKit

/// Drives the ImageKidInference engines and holds the editable working image
/// with an undo/redo history. All published state is main-actor isolated; the
/// heavy model work runs inside the engine actors.
@MainActor
final class InferenceModel: ObservableObject {
    @Published private(set) var sourceImage: UIImage?
    @Published private(set) var current: UIImage?
    @Published private(set) var videoURL: URL?
    @Published var statusText: String?
    @Published var progress: Double?
    @Published var isBusy = false
    @Published var errorMessage: String?

    private var undoStack: [UIImage] = []
    private var redoStack: [UIImage] = []

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

    /// The image currently shown and acted on.
    var workingImage: UIImage? { current }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEdited: Bool { canUndo || canRedo }

    // MARK: Source and history

    func setSource(_ image: UIImage) {
        videoURL = nil
        sourceImage = image
        current = image
        undoStack.removeAll()
        redoStack.removeAll()
        errorMessage = nil
        statusText = nil
        progress = nil
    }

    /// Switches to video mode (playback only — the image tools do not apply).
    func setVideo(_ url: URL) {
        videoURL = url
        sourceImage = nil
        current = nil
        undoStack.removeAll()
        redoStack.removeAll()
        errorMessage = nil
        statusText = "Video loaded"
        progress = nil
    }

    /// Commits a new working image and records the previous one for undo.
    private func commit(_ image: CGImage, status: String) {
        if let current { undoStack.append(current) }
        redoStack.removeAll()
        current = UIImage(cgImage: image)
        statusText = status
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        if let current { redoStack.append(current) }
        current = previous
        statusText = "Undo"
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        if let current { undoStack.append(current) }
        current = next
        statusText = "Redo"
    }

    func revertToOriginal() {
        guard let sourceImage, let current, current !== sourceImage else { return }
        undoStack.append(current)
        redoStack.removeAll()
        self.current = sourceImage
        statusText = "Reverted"
    }

    // MARK: Transform edits

    /// Applies a crop expressed as a normalised rectangle (top-left origin).
    func applyCrop(normalizedRect: CGRect) {
        guard let source = workingImage?.normalizedCGImage() else { return }
        let pixelRect = CGRect(
            x: normalizedRect.minX * CGFloat(source.width),
            y: normalizedRect.minY * CGFloat(source.height),
            width: normalizedRect.width * CGFloat(source.width),
            height: normalizedRect.height * CGFloat(source.height)
        ).integral
        guard let cropped = source.cropping(to: pixelRect) else { return }
        commit(cropped, status: "Cropped")
    }

    /// Resizes the working image to an exact pixel size.
    func applyResize(width: Int, height: Int) {
        guard let source = workingImage?.normalizedCGImage() else { return }
        guard let resized = source.resizedExact(width: width, height: height) else { return }
        commit(resized, status: "Resized to \(width)×\(height)")
    }

    /// Replaces the working image with an already-rendered edit (annotations,
    /// refinement).
    func applyEditedImage(_ image: CGImage, status: String) {
        commit(image, status: status)
    }

    // MARK: Inference edits

    func removeBackground(bestQuality: Bool) {
        run(status: "Done") { [self] progress in
            guard let source = workingImage?.normalizedCGImage() else {
                throw InferenceError.inputPreparationFailed
            }
            if bestQuality {
                return try await isnetRemover.removeBackground(from: source, progress: progress)
            }
            return try await visionRemover.removeBackground(from: source, progress: progress)
        }
    }

    func upscale(scale: CGFloat, bestQuality: Bool) {
        run(status: "Upscaled") { [self] progress in
            guard let source = workingImage?.normalizedCGImage() else {
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

    /// Runs an inference operation, wiring progress and committing the result.
    private func run(
        status: String,
        _ work: @escaping (@escaping InferenceProgressHandler) async throws -> CGImage
    ) {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
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
                commit(output, status: status)
            } catch {
                errorMessage = error.localizedDescription
                statusText = nil
            }
            progress = nil
            isBusy = false
        }
    }
}
