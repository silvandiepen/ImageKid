import Foundation

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

    static let baseURL = URL(string: "https://models-data.hakobs.com/v1")!

    static let files: [(remote: String, local: String)] = [
        ("Manifest.json", "Manifest.json"),
        ("model.mlmodel", "Data/com.apple.CoreML/model.mlmodel"),
        ("weight.bin", "Data/com.apple.CoreML/weights/weight.bin")
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
        Self.files.allSatisfy {
            FileManager.default.fileExists(atPath: localPackageURL.appendingPathComponent($0.local).path)
        }
    }
}

@MainActor
final class ModelDownloader: ObservableObject {
    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    @Published private(set) var states: [CoreMLModel: State] = [:]

    func state(_ model: CoreMLModel) -> State {
        if let state = states[model] { return state }
        return model.isDownloaded ? .ready : .notDownloaded
    }

    func download(_ model: CoreMLModel) {
        if case .downloading = state(model) { return }
        states[model] = .downloading(0)

        Task {
            do {
                let package = model.localPackageURL
                for (index, file) in CoreMLModel.files.enumerated() {
                    let remote = CoreMLModel.baseURL
                        .appendingPathComponent(model.rawValue)
                        .appendingPathComponent(file.remote)
                    let destination = package.appendingPathComponent(file.local)
                    try FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    let (temporary, response) = try await URLSession.shared.download(from: remote)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    states[model] = .downloading(Double(index + 1) / Double(CoreMLModel.files.count))
                }
                states[model] = .ready
            } catch {
                try? FileManager.default.removeItem(at: model.localPackageURL)
                states[model] = .failed(error.localizedDescription)
            }
        }
    }

    func remove(_ model: CoreMLModel) {
        try? FileManager.default.removeItem(at: model.localPackageURL)
        let compiled = model.localPackageURL
            .deletingPathExtension()
            .appendingPathExtension("mlmodelc")
        try? FileManager.default.removeItem(at: compiled)
        states[model] = .notDownloaded
    }
}
