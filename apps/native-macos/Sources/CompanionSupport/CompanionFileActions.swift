import AppKit
import Foundation

/// Finder/Workspace side effects the queue rows trigger. Kept out of the views so
/// they stay declarative and so both companion apps share one behaviour.
enum CompanionFileActions {
    static func open(_ urls: [URL]) {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }

    static func revealInFinder(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }
}
