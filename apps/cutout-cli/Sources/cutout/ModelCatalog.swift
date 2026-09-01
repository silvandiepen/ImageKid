import Foundation

/// Where ImageKid and the companion apps keep downloaded Core ML packages.
///
/// The apps reach this folder through the `group.com.hakobs.imagekid` App Group.
/// A command-line tool is not sandboxed and has no group entitlement, so it
/// addresses the same container by path and falls back to the unsandboxed
/// Application Support location the apps use when no group container exists.
enum ModelCatalog {
    static let birefnetPackageName = "BiRefNet.mlpackage"

    static var searchDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home
                .appendingPathComponent("Library/Group Containers", isDirectory: true)
                .appendingPathComponent("group.com.hakobs.imagekid", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true),
            home
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("ImageKid", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        ]
    }

    /// The installed BiRefNet package, or nil when Best Quality was never installed.
    static func birefnetPackageURL() -> URL? {
        searchDirectories
            .map { $0.appendingPathComponent(birefnetPackageName, isDirectory: true) }
            .first { isCompletePackage($0) }
    }

    private static func isCompletePackage(_ url: URL) -> Bool {
        let required = [
            "Manifest.json",
            "Data/com.apple.CoreML/model.mlmodel",
            "Data/com.apple.CoreML/weights/weight.bin"
        ]
        return required.allSatisfy {
            FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path)
        }
    }
}
