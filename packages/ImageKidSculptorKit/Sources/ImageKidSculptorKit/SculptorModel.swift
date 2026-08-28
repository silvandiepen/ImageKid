import Foundation

/// The reconstruction model, and where it lives on disk.
///
/// Mirrors ImageKid's existing Core ML registry (`CoreMLModel` in
/// `CompanionCoreMLModels.swift`): the weights are not shipped in the app, they
/// are downloaded on first use into the shared App Group. Sculptor's are much
/// larger, so the UI must show size and disk usage and offer removal.
public enum SculptorModel: String, CaseIterable, Identifiable, Sendable {
    case triposr = "TripoSR"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .triposr: "3D Reconstruction"
        }
    }

    public var approximateSize: String {
        switch self {
        case .triposr: "1.6 GB"
        }
    }

    /// Bump alongside the download manifest so an outdated install reads as
    /// missing rather than being loaded blindly.
    public var version: String {
        switch self {
        case .triposr: "v1"
        }
    }

    /// Files that must all be present for the model to count as installed.
    public var files: [String] {
        switch self {
        case .triposr: ["config.yaml", "model.ckpt"]
        }
    }

    public static let appGroupIdentifier = "group.com.hakobs.imagekid"

    /// Root holding every Sculptor model, inside the App Group so the main app
    /// and the companions share one cache.
    public static var modelsDirectory: URL {
        let fileManager = FileManager.default
        if let shared = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return shared
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent("Sculptor", isDirectory: true)
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImageKid", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Sculptor", isDirectory: true)
    }

    public var directory: URL {
        Self.modelsDirectory
            .appendingPathComponent(rawValue, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    public var isInstalled: Bool {
        let fileManager = FileManager.default
        return files.allSatisfy {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    /// Bytes currently on disk for this model, for the Settings display.
    public var installedBytes: Int64 {
        let fileManager = FileManager.default
        return files.reduce(into: Int64(0)) { total, name in
            let path = directory.appendingPathComponent(name).path
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            total += (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
    }
}
