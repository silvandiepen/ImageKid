import AppKit
import CoreML
import Foundation
import ImageKidInference
import UniformTypeIdentifiers

@MainActor
final class CompanionBatchModel: ObservableObject {
    enum UpscaleEngine: String, CaseIterable, Identifiable {
        case standard
        case bestQuality

        var id: String { rawValue }

        var label: String {
            switch self {
            case .standard: "Standard"
            case .bestQuality: "Best Quality"
            }
        }
    }

    enum CutoutEngine: String, CaseIterable, Identifiable {
        case builtIn
        case bestQuality

        var id: String { rawValue }

        var label: String {
            switch self {
            case .builtIn: "Built-in"
            case .bestQuality: "Best Quality"
            }
        }
    }

    enum Operation {
        case upscale(scale: Int, contentMode: UpscaleContentMode, engine: UpscaleEngine)
        case cutout(engine: CutoutEngine)
    }

    @Published var items: [BatchItem] = []
    @Published var customDestinationURL: URL?
    @Published var overwriteOriginals = false
    @Published var isProcessing = false
    @Published var overallProgress = 0.0

    private var processingTask: Task<Void, Never>?

    func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = CompanionImageIO.readableTypes
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            customDestinationURL = panel.url
        }
    }

    func addFiles(_ urls: [URL]) {
        let existing = Set(items.map(\.sourceURL))
        let newItems = urls
            .filter { url in
                guard !existing.contains(url) else { return false }
                return CompanionImageIO.readableTypes.contains { url.conforms(to: $0) }
            }
            .map { url in
                var item = BatchItem(sourceURL: url)
                if let properties = CompanionImageIO.properties(at: url) {
                    item.pixelSize = CGSize(width: properties.width, height: properties.height)
                }
                item.thumbnail = CompanionImageIO.thumbnail(at: url)
                return item
            }
        items.append(contentsOf: newItems)
    }

    func removeItem(_ id: BatchItem.ID) {
        guard !isProcessing else { return }
        items.removeAll { $0.id == id }
    }

    func clearCompleted() {
        guard !isProcessing else { return }
        items.removeAll {
            if case .done = $0.state { return true }
            return false
        }
    }

    func cancel() {
        processingTask?.cancel()
    }

    func generate(operation: Operation) {
        guard !items.isEmpty, !isProcessing else { return }
        isProcessing = true
        overallProgress = 0
        processingTask = Task {
            defer {
                isProcessing = false
                processingTask = nil
                overallProgress = 1
            }

            let total = max(items.count, 1)
            for index in items.indices {
                if Task.isCancelled {
                    update(index: index, state: .failed(CompanionProcessingError.cancelled.localizedDescription))
                    continue
                }

                update(index: index, state: .processing("Opening image", nil))
                do {
                    let output = try await processItem(at: index, operation: operation)
                    update(index: index, state: .done(output))
                } catch is CancellationError {
                    update(index: index, state: .failed(CompanionProcessingError.cancelled.localizedDescription))
                } catch {
                    update(index: index, state: .failed(error.localizedDescription))
                }
                overallProgress = Double(index + 1) / Double(total)
            }
        }
    }

    private func processItem(at index: Int, operation: Operation) async throws -> URL {
        let sourceURL = items[index].sourceURL
        let customDestinationURL = customDestinationURL
        let overwriteOriginals = overwriteOriginals

        return try await Task.detached(priority: .userInitiated) {
            if Task.isCancelled { throw CancellationError() }
            let source = try CompanionImageIO.loadImage(at: sourceURL)

            switch operation {
            case .upscale(let scale, let contentMode, let engine):
                let target = CGSize(width: source.width * scale, height: source.height * scale)
                let resolved = UpscaleContentMode.resolved(contentMode, for: source)
                let output: CGImage
                if engine == .bestQuality && resolved != .textAndUI {
                    guard CoreMLModel.realESRGAN.isDownloaded else {
                        throw CompanionProcessingError.modelMissing("Install Best Quality first.")
                    }
                    let upscaler = CoreMLUpscaler(
                        modelProvider: PackageModelProvider(packageURL: CoreMLModel.realESRGAN.localPackageURL),
                        configuration: CoreMLUpscalerConfiguration(fixedInputSize: CGSize(width: 256, height: 256))
                    )
                    output = try await upscaler.upscale(source, to: target) { progress in
                        Task { @MainActor in
                            self.update(index: index, state: .processing(progress.detail, progress.fraction))
                        }
                    }
                } else {
                    let sharpening: CoreImageUpscaler.Sharpening = resolved == .textAndUI ? .textAndUI : .photoArtwork
                    let upscaler = CoreImageUpscaler(sharpening: sharpening)
                    output = try await upscaler.upscale(source, to: target) { progress in
                        Task { @MainActor in
                            self.update(index: index, state: .processing(progress.detail, progress.fraction))
                        }
                    }
                }
                let url = try CompanionImageIO.destinationURL(
                    for: sourceURL,
                    operationFolderName: "ImageKid Upscaled",
                    suffix: "-\(scale)x",
                    extension: sourceURL.preferredRasterExtension(defaultExtension: "png"),
                    customFolder: customDestinationURL,
                    overwriteOriginals: overwriteOriginals
                )
                try CompanionImageIO.writeImagePreservingPreferredFormat(output, to: url)
                return url

            case .cutout(let engine):
                let output: CGImage
                if engine == .bestQuality {
                    guard CoreMLModel.birefnet.isDownloaded else {
                        throw CompanionProcessingError.modelMissing("Install Best Quality first.")
                    }
                    let configuration = MLModelConfiguration()
                    configuration.computeUnits = .cpuOnly
                    let remover = CoreMLBackgroundRemover(
                        modelProvider: PackageModelProvider(
                            packageURL: CoreMLModel.birefnet.localPackageURL,
                            configuration: configuration
                        )
                    )
                    output = try await remover.removeBackground(from: source) { progress in
                        Task { @MainActor in
                            self.update(index: index, state: .processing(progress.detail, progress.fraction))
                        }
                    }
                } else {
                    let remover = VisionBackgroundRemover()
                    output = try await remover.removeBackground(from: source) { progress in
                        Task { @MainActor in
                            self.update(index: index, state: .processing(progress.detail, progress.fraction))
                        }
                    }
                }
                let url = try CompanionImageIO.destinationURL(
                    for: sourceURL,
                    operationFolderName: "ImageKid Cutouts",
                    suffix: "-cutout",
                    extension: "png",
                    customFolder: customDestinationURL,
                    overwriteOriginals: overwriteOriginals
                )
                try CompanionImageIO.writePNG(output, to: url)
                return url
            }
        }.value
    }

    private func update(index: Int, state: BatchItem.State) {
        guard items.indices.contains(index) else { return }
        items[index].state = state
    }
}

private extension URL {
    func conforms(to type: UTType) -> Bool {
        guard let contentType = try? resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return contentType.conforms(to: type)
    }

    func preferredRasterExtension(defaultExtension: String) -> String {
        let value = pathExtension.lowercased()
        if ["jpg", "jpeg", "png"].contains(value) {
            return value == "jpg" ? "jpeg" : value
        }
        return defaultExtension
    }
}

private extension CompanionImageIO {
    static func writeImagePreservingPreferredFormat(_ image: CGImage, to url: URL) throws {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            try writeJPEG(image, to: url)
        default:
            try writePNG(image, to: url)
        }
    }
}
