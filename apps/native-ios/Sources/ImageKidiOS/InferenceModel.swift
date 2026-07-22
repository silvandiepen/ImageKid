import CoreGraphics
import CoreML
import Foundation
import ImageKidInference
import UIKit

/// The background-removal engine the user can pick.
enum BackgroundEngine: String, CaseIterable, Identifiable {
    case vision    // Built-in, Apple Vision — always available.
    case birefnet  // Best quality, BiRefNet (MIT).
    case u2net     // U²-Net (Apache-2.0).

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vision: "Built-in (Vision)"
        case .birefnet: "Best (BiRefNet)"
        case .u2net: "U²-Net"
        }
    }

    var systemImage: String {
        self == .vision ? "person.crop.rectangle" : "sparkles"
    }
}

/// Quality grade for Magic ▸ Enhance Image. We surface grades, not model names:
/// Quick is the built-in Core Image sharpen (instant, no download); High and Max
/// are on-device AI models downloaded on demand.
enum EnhanceQuality: String, CaseIterable, Identifiable {
    case quick
    case high
    case max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: "Quick"
        case .high: "High"
        case .max: "Max"
        }
    }

    var detail: String {
        switch self {
        case .quick: "Instant. Built-in, no download."
        case .high: "Sharper AI detail."
        case .max: "Richest, most realistic detail."
        }
    }

    /// The model this grade needs downloaded (nil = built-in Core Image).
    var requiredModel: ModelDownloader.Model? {
        switch self {
        case .quick: nil
        case .high: .realESRGAN
        case .max: .auraSR
        }
    }
}

/// Output size for Enhance. AI models always upscale 4×; we fit the result to
/// the requested multiple of the source.
enum EnhanceSize: String, CaseIterable, Identifiable {
    case same
    case x2
    case x4

    var id: String { rawValue }

    var label: String {
        switch self {
        case .same: "Same"
        case .x2: "2×"
        case .x4: "4×"
        }
    }

    var factor: CGFloat {
        switch self {
        case .same: 1
        case .x2: 2
        case .x4: 4
        }
    }
}

/// One picture the user is working on: its original, current edit, per-item
/// undo/redo history, and saved colour swatches. Value type so mutations flow
/// through the model's `@Published items` array and republish to SwiftUI.
struct EditorItem: Identifiable {
    let id = UUID()
    let sourceImage: UIImage
    var current: UIImage
    var undoStack: [UIImage] = []
    var redoStack: [UIImage] = []
    var sampledColors: [SampledColor] = []
    /// Non-destructive annotations (text/shapes) layered over `current`. Kept
    /// editable and only flattened into pixels on export — never baked in place.
    var annotations: [Annotation] = []
    /// The working image captured immediately before the last background removal,
    /// used as the restore source in Refine (may be cropped, unlike `sourceImage`).
    var preRemovalImage: UIImage?

    init(source: UIImage) {
        self.sourceImage = source
        self.current = source
    }
}

/// Drives the ImageKidInference engines and holds a list of pictures being
/// edited, each with its own undo/redo history. All published state is
/// main-actor isolated; the heavy model work runs inside the engine actors.
@MainActor
final class InferenceModel: ObservableObject {
    /// Every picture the user has opened this session (the iOS "workspace").
    @Published var items: [EditorItem] = []
    @Published var selectedItemID: UUID?
    @Published private(set) var videoURL: URL?
    @Published var statusText: String?
    @Published var progress: Double?
    @Published var isBusy = false
    @Published var errorMessage: String?

    private var activeIndex: Int? {
        guard let selectedItemID else { return nil }
        return items.firstIndex { $0.id == selectedItemID }
    }

    var active: EditorItem? { activeIndex.map { items[$0] } }

    // Built-in engines: always available, no model download.
    private let visionRemover = VisionBackgroundRemover()

    // Best Quality engines download their Core ML models on demand from R2 (see
    // ModelDownloader) and cache them in Application Support. Until a model is
    // downloaded, its engine is unavailable.
    //
    // BiRefNet must run in fp32 on the CPU, NOT the Neural Engine or GPU: those
    // run it in fp16 and overflow on high-activation regions (its Swin backbone),
    // producing NaNs that wipe the mask. CPU is fp32 and correct. U²-Net and
    // Real-ESRGAN are plain CNNs with bounded activations — they stay on the fast
    // default (Neural Engine) path.
    private static func cpuOnlyConfiguration() -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        return configuration
    }

    let downloader = ModelDownloader()

    // Providers point at the downloaded package in Application Support. They report
    // unavailable until the model files are present, then compile on first use.
    private lazy var birefnetProvider = PackageModelProvider(
        packageURL: downloader.localPackageURL(for: .birefnet),
        configuration: InferenceModel.cpuOnlyConfiguration()
    )
    private lazy var u2netProvider = PackageModelProvider(
        packageURL: downloader.localPackageURL(for: .u2net)
    )
    private lazy var realESRGANProvider = PackageModelProvider(
        packageURL: downloader.localPackageURL(for: .realESRGAN)
    )
    private lazy var birefnetRemover = CoreMLBackgroundRemover(modelProvider: birefnetProvider)
    private lazy var u2netRemover = CoreMLBackgroundRemover(
        modelProvider: u2netProvider,
        configuration: CoreMLBackgroundRemoverConfiguration(inputSize: CGSize(width: 320, height: 320))
    )
    // The RealESRGAN model has a fixed 256×256 input (the reliable conversion
    // path); the tiler resizes each tile to match. Keep in sync with
    // tools/coreml-conversion (`--fixed-size 256`).
    private lazy var realESRGANUpscaler = CoreMLUpscaler(
        modelProvider: realESRGANProvider,
        configuration: CoreMLUpscalerConfiguration(
            fixedInputSize: CGSize(width: 256, height: 256)
        )
    )
    private lazy var auraSRProvider = PackageModelProvider(
        packageURL: downloader.localPackageURL(for: .auraSR)
    )
    // AuraSR-v2 (GigaGAN) has a fixed 64×64 input → 256×256 out (native 4×). The
    // tiler feeds 64×64 tiles. Keep in sync with tools/coreml-conversion
    // (`convert_aurasr.py`, INPUT_SIZE = 64).
    private lazy var auraSRUpscaler = CoreMLUpscaler(
        modelProvider: auraSRProvider,
        configuration: CoreMLUpscalerConfiguration(
            nativeScale: 4,
            tileSize: 64,
            fixedInputSize: CGSize(width: 64, height: 64)
        )
    )

    /// Background engines available now (Vision always; Core ML ones when downloaded).
    var availableBackgroundEngines: [BackgroundEngine] {
        BackgroundEngine.allCases.filter { engine in
            switch engine {
            case .vision: true
            case .birefnet: downloader.isDownloaded(.birefnet)
            case .u2net: downloader.isDownloaded(.u2net)
            }
        }
    }

    var bestQualityUpscaleAvailable: Bool { downloader.isDownloaded(.realESRGAN) }

    init() {
        // Re-publish so views observing this model update as downloads progress.
        downloader.onChange = { [weak self] in self?.objectWillChange.send() }
    }

    /// The original and current image of the selected picture.
    var sourceImage: UIImage? { active?.sourceImage }
    var current: UIImage? { active?.current }

    /// The image currently shown and acted on.
    var workingImage: UIImage? { current }

    /// Non-destructive annotations for the selected picture (persist, editable).
    var annotations: [Annotation] {
        get { active?.annotations ?? [] }
        set { if let i = activeIndex { items[i].annotations = newValue } }
    }

    var canUndo: Bool { active.map { !$0.undoStack.isEmpty } ?? false }
    var canRedo: Bool { active.map { !$0.redoStack.isEmpty } ?? false }
    var isEdited: Bool { canUndo || canRedo }

    /// Saved colour swatches for the selected picture (persist across sheets).
    var sampledColors: [SampledColor] { active?.sampledColors ?? [] }

    /// Restore source for Refine: the working image just before background removal
    /// (falls back to the original if none was captured).
    var refineRestoreImage: UIImage? { active?.preRemovalImage ?? active?.sourceImage }

    // MARK: Workspace (list of pictures)

    /// Adds a picture to the workspace and selects it for editing.
    func setSource(_ image: UIImage) {
        videoURL = nil
        let item = EditorItem(source: image)
        items.append(item)
        selectedItemID = item.id
        errorMessage = nil
        statusText = nil
        progress = nil
    }

    func selectItem(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        videoURL = nil
        selectedItemID = id
        statusText = nil
        progress = nil
    }

    func removeItem(_ id: UUID) {
        items.removeAll { $0.id == id }
        if selectedItemID == id {
            selectedItemID = items.last?.id
        }
    }

    /// Opens an image handed to ImageKid by another app ("Open in" / share sheet).
    func openExternalImage(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            errorMessage = "Couldn't open that image."
            return
        }
        setSource(image)
    }

    /// Switches to video mode (playback only — the image tools do not apply).
    func setVideo(_ url: URL) {
        videoURL = url
        errorMessage = nil
        statusText = "Video loaded"
        progress = nil
    }

    // MARK: Colour swatches

    func addSampledColor(_ colour: SampledColor) {
        guard let index = activeIndex else { return }
        items[index].sampledColors.append(colour)
    }

    func removeSampledColor(_ id: UUID) {
        guard let index = activeIndex else { return }
        items[index].sampledColors.removeAll { $0.id == id }
    }

    func clearSampledColors() {
        guard let index = activeIndex else { return }
        items[index].sampledColors.removeAll()
    }

    // MARK: History

    /// Commits a new working image to a specific picture (defaults to the selected
    /// one). Async operations pass the id captured when they started so a result
    /// never lands on a picture the user selected while it was running.
    private func commit(_ image: CGImage, status: String, to itemID: UUID? = nil) {
        let targetID = itemID ?? selectedItemID
        guard let index = items.firstIndex(where: { $0.id == targetID }) else { return }
        items[index].undoStack.append(items[index].current)
        items[index].redoStack.removeAll()
        items[index].current = UIImage(cgImage: image)
        if selectedItemID == targetID {
            statusText = status
        }
    }

    func undo() {
        guard let index = activeIndex, let previous = items[index].undoStack.popLast() else { return }
        items[index].redoStack.append(items[index].current)
        items[index].current = previous
        statusText = "Undo"
    }

    func redo() {
        guard let index = activeIndex, let next = items[index].redoStack.popLast() else { return }
        items[index].undoStack.append(items[index].current)
        items[index].current = next
        statusText = "Redo"
    }

    func revertToOriginal() {
        guard let index = activeIndex, items[index].current !== items[index].sourceImage else { return }
        items[index].undoStack.append(items[index].current)
        items[index].redoStack.removeAll()
        items[index].current = items[index].sourceImage
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

    func removeBackground(engine: BackgroundEngine) {
        // Capture the working image now so Refine can restore from the exact
        // pre-removal pixels (which may already be cropped), not the full original.
        if let index = activeIndex {
            items[index].preRemovalImage = items[index].current
        }
        run(status: "Background removed") { [self] progress in
            guard let source = workingImage?.normalizedCGImage() else {
                throw InferenceError.inputPreparationFailed
            }
            switch engine {
            case .vision:
                return try await visionRemover.removeBackground(from: source, progress: progress)
            case .birefnet:
                return try await birefnetRemover.removeBackground(from: source, progress: progress)
            case .u2net:
                return try await u2netRemover.removeBackground(from: source, progress: progress)
            }
        }
    }

    /// Whether a quality grade is ready to run now (built-in, or model downloaded).
    func enhanceReady(_ quality: EnhanceQuality) -> Bool {
        guard let model = quality.requiredModel else { return true }
        return downloader.isDownloaded(model)
    }

    /// Magic ▸ Enhance Image. Improves detail (and optionally enlarges) using the
    /// chosen quality grade. AI grades upscale 4× natively, then we fit to the
    /// requested output size.
    func enhance(quality: EnhanceQuality, size: EnhanceSize) {
        run(status: "Enhanced") { [self] progress in
            guard let source = workingImage?.normalizedCGImage() else {
                throw InferenceError.inputPreparationFailed
            }
            let target = CGSize(
                width: CGFloat(source.width) * size.factor,
                height: CGFloat(source.height) * size.factor
            )
            switch quality {
            case .quick:
                let resolved = UpscaleContentMode.resolved(.automatic, for: source)
                let sharpening: CoreImageUpscaler.Sharpening = resolved == .textAndUI ? .textAndUI : .photoArtwork
                return try await CoreImageUpscaler(sharpening: sharpening)
                    .upscale(source, to: target, progress: progress)
            case .high:
                return try await realESRGANUpscaler.upscale(source, to: target, progress: progress)
            case .max:
                return try await auraSRUpscaler.upscale(source, to: target, progress: progress)
            }
        }
    }

    /// Prompted editing via OpenAI. Sends the working image and prompt only when
    /// the user starts this action, using their own key.
    func promptEdit(prompt: String, apiKey: String) {
        run(status: "AI edit") { _ in
            guard let source = self.workingImage?.normalizedCGImage() else {
                throw InferenceError.inputPreparationFailed
            }
            return try await OpenAIImageEditProvider(apiKey: apiKey).edit(source, prompt: prompt)
        }
    }

    /// Runs an inference operation, wiring progress and committing the result.
    private func run(
        status: String,
        _ work: @escaping (@escaping InferenceProgressHandler) async throws -> CGImage
    ) {
        guard !isBusy else { return }
        // Remember which picture this operation belongs to; the user may select a
        // different one before it finishes.
        let targetID = selectedItemID
        isBusy = true
        errorMessage = nil
        progress = nil
        statusText = "Working…"

        let handler: InferenceProgressHandler = { [weak self] update in
            Task { @MainActor in
                guard self?.selectedItemID == targetID else { return }
                self?.statusText = update.detail
                self?.progress = update.fraction
            }
        }

        Task {
            do {
                let output = try await work(handler)
                commit(output, status: status, to: targetID)
            } catch {
                if selectedItemID == targetID {
                    errorMessage = error.localizedDescription
                    statusText = nil
                }
            }
            progress = nil
            isBusy = false
        }
    }
}
