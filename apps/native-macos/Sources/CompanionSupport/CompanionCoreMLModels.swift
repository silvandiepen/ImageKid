import AppKit
import Foundation
import UniformTypeIdentifiers

/// Companion-app copy of the model registry. It intentionally mirrors ImageKid's
/// main target so separate app modules can share the same App Group cache.
enum CoreMLModel: String, CaseIterable, Identifiable {
    case birefnet = "BiRefNet"
    case realESRGAN = "RealESRGAN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .birefnet: "Best Cutout"
        case .realESRGAN: "Best Upscale"
        }
    }

    var approxSize: String {
        switch self {
        case .birefnet: "179 MB"
        case .realESRGAN: "33 MB"
        }
    }

    static let requiredFiles = [
        "Manifest.json",
        "Data/com.apple.CoreML/model.mlmodel",
        "Data/com.apple.CoreML/weights/weight.bin"
    ]

    static var modelsDirectory: URL {
        let fileManager = FileManager.default
        if let sharedContainer = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.hakobs.imagekid") {
            return sharedContainer.appendingPathComponent("Models", isDirectory: true)
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("ImageKid", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    var localPackageURL: URL {
        Self.modelsDirectory.appendingPathComponent("\(rawValue).mlpackage", isDirectory: true)
    }

    var isDownloaded: Bool {
        Self.isValidPackage(at: localPackageURL)
    }

    static func isValidPackage(at url: URL, fileManager: FileManager = .default) -> Bool {
        requiredFiles.allSatisfy {
            fileManager.fileExists(atPath: url.appendingPathComponent($0).path)
        }
    }
}

@MainActor
final class ModelInstaller: ObservableObject {
    enum State: Equatable {
        case notInstalled
        case installing
        case ready
        case failed(String)
    }

    @Published private(set) var states: [CoreMLModel: State] = [:]

    func state(_ model: CoreMLModel) -> State {
        if let state = states[model] { return state }
        return model.isDownloaded ? .ready : .notInstalled
    }

    func choosePackage(for model: CoreMLModel) {
        if case .installing = state(model) { return }

        let panel = NSOpenPanel()
        panel.title = "Import \(model.title)"
        panel.message = "Choose a compatible \(model.rawValue).mlpackage. The package is copied into ImageKid's local model library."
        panel.prompt = "Import Model"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let packageType = UTType(filenameExtension: "mlpackage") {
            panel.allowedContentTypes = [packageType]
        }
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        states[model] = .installing

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try Self.install(model, from: sourceURL)
                }.value
                states[model] = .ready
            } catch {
                states[model] = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated private static func install(_ model: CoreMLModel, from sourceURL: URL) throws {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        guard CoreMLModel.isValidPackage(at: sourceURL) else {
            throw ModelImportError.incompletePackage
        }

        let fileManager = FileManager.default
        let destination = model.localPackageURL
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(
            ".\(model.rawValue)-\(UUID().uuidString).mlpackage",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: sourceURL, to: staging)
        guard CoreMLModel.isValidPackage(at: staging) else {
            throw ModelImportError.incompletePackage
        }

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    func remove(_ model: CoreMLModel) {
        do {
            if FileManager.default.fileExists(atPath: model.localPackageURL.path) {
                try FileManager.default.removeItem(at: model.localPackageURL)
            }
            let compiled = model.localPackageURL
                .deletingPathExtension()
                .appendingPathExtension("mlmodelc")
            if FileManager.default.fileExists(atPath: compiled.path) {
                try FileManager.default.removeItem(at: compiled)
            }
            states[model] = .notInstalled
        } catch {
            states[model] = .failed(error.localizedDescription)
        }
    }
}

private enum ModelImportError: LocalizedError {
    case incompletePackage

    var errorDescription: String? {
        switch self {
        case .incompletePackage:
            "That Core ML package is incomplete or is not compatible with this ImageKid tool."
        }
    }
}
