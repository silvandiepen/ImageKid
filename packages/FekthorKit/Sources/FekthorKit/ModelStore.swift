import Foundation

/// Optional on-device model lookup (docs/AI.md, docs/PRIVACY-SECURITY.md):
/// models are never bundled, required, or downloaded at runtime — the app is
/// strictly local-first. A user who wants a model places its compiled
/// `.mlmodelc` in Application Support; every feature degrades cleanly when
/// its model is absent.
public enum ModelStore {
    public enum Model: String, CaseIterable, Sendable {
        case realESRGAN = "RealESRGAN"
    }

    /// Where models are looked up: `~/Library/Application Support` (or the
    /// sandbox container's equivalent) `/Fekthor/Models`.
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fekthor/Models", isDirectory: true)
    }

    public static func compiledURL(_ model: Model) -> URL {
        directory.appendingPathComponent("\(model.rawValue).mlmodelc", isDirectory: true)
    }
}
