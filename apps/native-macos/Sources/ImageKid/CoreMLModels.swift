import Foundation

/// The optional Core ML models ImageKid downloads on demand (never shipped in the
/// binary), cached in Application Support. Mirrors the iOS app so both platforms
/// use the same models and the same R2 layout (`v1/<Name>/…`).
enum CoreMLModel: String, CaseIterable, Identifiable {
    case birefnet = "BiRefNet"
    case u2net = "U2Net"
    case realESRGAN = "RealESRGAN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .birefnet: "BiRefNet — best background"
        case .u2net: "U²-Net — background"
        case .realESRGAN: "Real-ESRGAN — 4× upscale"
        }
    }

    var approxSize: String {
        switch self {
        case .birefnet: "179 MB"
        case .u2net: "88 MB"
        case .realESRGAN: "33 MB"
        }
    }

    /// Public R2 custom domain. Models live under `v1/<Name>/…`.
    static let baseURL = URL(string: "https://models-data.hakobs.com/v1")!

    /// Each single-model `.mlpackage` is these three files (remote → local path).
    static let files: [(remote: String, local: String)] = [
        ("Manifest.json", "Manifest.json"),
        ("model.mlmodel", "Data/com.apple.CoreML/model.mlmodel"),
        ("weight.bin", "Data/com.apple.CoreML/weights/weight.bin")
    ]

    static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Models", isDirectory: true)
    }

    var localPackageURL: URL {
        Self.modelsDirectory.appendingPathComponent("\(rawValue).mlpackage", isDirectory: true)
    }

    /// A model is usable once all of its files are on disk. Pure filesystem check,
    /// safe to call from any thread (the background-removal/upscale services do).
    var isDownloaded: Bool {
        Self.files.allSatisfy {
            FileManager.default.fileExists(atPath: localPackageURL.appendingPathComponent($0.local).path)
        }
    }
}

/// Downloads and manages the optional Core ML models, publishing progress for the
/// Settings UI.
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
                // Drop a partial download so `isDownloaded` stays honest.
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
