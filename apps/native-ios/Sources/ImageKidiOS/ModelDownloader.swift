import Foundation

/// Downloads the Best Quality Core ML models on demand from R2
/// (models-data.hakobs.com) and caches them in Application Support, so they don't
/// bloat the app binary. A `.mlpackage` is just three files, downloaded and
/// reassembled into the package layout `PackageModelProvider` expects.
@MainActor
final class ModelDownloader: ObservableObject {
    enum Model: String, CaseIterable, Identifiable {
        case birefnet = "BiRefNet"
        case u2net = "U2Net"
        case realESRGAN = "RealESRGAN"
        case auraSR = "AuraSR"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .birefnet: "BiRefNet — best background"
            case .u2net: "U²-Net — background"
            case .realESRGAN: "Real-ESRGAN — 4× upscale"
            case .auraSR: "AuraSR — best quality"
            }
        }

        var approxSize: String {
            switch self {
            case .birefnet: "179 MB"
            case .u2net: "88 MB"
            case .realESRGAN: "33 MB"
            case .auraSR: "196 MB"
            }
        }
    }

    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    /// Public R2 custom domain. Models live under `v1/<Name>/…`.
    static let baseURL = URL(string: "https://models-data.hakobs.com/v1")!

    /// Each single-model `.mlpackage` is these three files (remote name → local
    /// path inside the package).
    private static let files: [(remote: String, local: String)] = [
        ("Manifest.json", "Manifest.json"),
        ("model.mlmodel", "Data/com.apple.CoreML/model.mlmodel"),
        ("weight.bin", "Data/com.apple.CoreML/weights/weight.bin")
    ]

    /// Called after any state change so an owner (InferenceModel) can re-publish.
    var onChange: (() -> Void)?

    @Published private(set) var states: [Model: State] = [:] {
        didSet { onChange?() }
    }

    private var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Models", isDirectory: true)
    }

    func localPackageURL(for model: Model) -> URL {
        modelsDirectory.appendingPathComponent("\(model.rawValue).mlpackage", isDirectory: true)
    }

    /// A model is usable once all of its files are on disk.
    func isDownloaded(_ model: Model) -> Bool {
        let package = localPackageURL(for: model)
        return Self.files.allSatisfy {
            FileManager.default.fileExists(atPath: package.appendingPathComponent($0.local).path)
        }
    }

    func state(_ model: Model) -> State {
        if let state = states[model] { return state }
        return isDownloaded(model) ? .ready : .notDownloaded
    }

    func download(_ model: Model) {
        if case .downloading = state(model) { return }
        states[model] = .downloading(0)

        Task {
            do {
                let package = localPackageURL(for: model)
                for (index, file) in Self.files.enumerated() {
                    let remote = Self.baseURL
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
                    states[model] = .downloading(Double(index + 1) / Double(Self.files.count))
                }
                states[model] = .ready
            } catch {
                // Drop a partial download so `isDownloaded` stays honest.
                try? FileManager.default.removeItem(at: localPackageURL(for: model))
                states[model] = .failed(error.localizedDescription)
            }
        }
    }

    func remove(_ model: Model) {
        try? FileManager.default.removeItem(at: localPackageURL(for: model))
        // PackageModelProvider caches the compiled model next to the package.
        let compiled = localPackageURL(for: model)
            .deletingPathExtension()
            .appendingPathExtension("mlmodelc")
        try? FileManager.default.removeItem(at: compiled)
        states[model] = .notDownloaded
    }
}
