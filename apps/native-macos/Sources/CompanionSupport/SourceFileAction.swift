import Foundation

/// What a run should do with each input file once its result has been written.
/// Off by default: the queue never touches the originals unless it is asked to.
enum SourceFileAction: String, CaseIterable, Identifiable {
    case keep
    case move
    case copy
    case trash
    case delete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keep: "Leave originals where they are"
        case .move: "Move originals to folder..."
        case .copy: "Copy originals to folder..."
        case .trash: "Move originals to Trash"
        case .delete: "Delete originals permanently"
        }
    }

    /// Move and Copy are meaningless without somewhere to put the file.
    var needsFolder: Bool {
        self == .move || self == .copy
    }

    /// True when the original stops being where it was, which needs write access to the
    /// folder around it — something dropping a file does not grant.
    var removesOriginal: Bool {
        self == .move || self == .trash || self == .delete
    }

    /// Shown under the picker so an armed destructive action is never invisible.
    var warning: String? {
        switch self {
        case .trash: "Originals go to the Trash as soon as their result is written."
        case .delete: "Originals are erased as soon as their result is written. This cannot be undone."
        default: nil
        }
    }
}

/// Where an input file ended up. `relocated` carries the new location so the queue row
/// keeps pointing at a file that still exists.
enum SourceFileOutcome: Equatable {
    case kept(reason: String?)
    case relocated(URL)
    case copied(URL)
    case trashed
    case deleted

    var note: String? {
        switch self {
        case .kept(let reason): reason
        case .relocated(let url): "Original moved to \u{201C}\(url.deletingLastPathComponent().lastPathComponent)\u{201D}"
        case .copied(let url): "Original copied to \u{201C}\(url.deletingLastPathComponent().lastPathComponent)\u{201D}"
        case .trashed: "Original moved to the Trash"
        case .deleted: "Original deleted"
        }
    }
}

enum SourceFileActionError: LocalizedError {
    case folderNotChosen
    case failed(action: SourceFileAction, reason: String)

    var errorDescription: String? {
        switch self {
        case .folderNotChosen:
            "Choose a folder for the originals under When Done."
        case .failed(let action, let reason):
            switch action {
            case .move: "Could not move the original: \(reason)"
            case .copy: "Could not copy the original: \(reason)"
            case .trash: "Could not trash the original: \(reason)"
            case .delete: "Could not delete the original: \(reason)"
            case .keep: reason
            }
        }
    }
}

/// Runs a `SourceFileAction` against one input file. Pure `FileManager` work, kept out of
/// the model so it can be tested without a batch or a sandbox around it.
enum SourceFileActionRunner {
    static func apply(
        _ action: SourceFileAction,
        to source: URL,
        folder: URL?,
        fileManager: FileManager = .default
    ) throws -> SourceFileOutcome {
        switch action {
        case .keep:
            return .kept(reason: nil)

        case .move, .copy:
            guard let folder else { throw SourceFileActionError.folderNotChosen }
            if action == .move, folder.standardizedFileURL == source.deletingLastPathComponent().standardizedFileURL {
                return .kept(reason: "Original is already in that folder")
            }
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = CompanionImageIO.uniqueURL(
                    for: folder.appendingPathComponent(source.lastPathComponent),
                    fileManager: fileManager
                )
                if action == .move {
                    try fileManager.moveItem(at: source, to: target)
                    return .relocated(target)
                }
                try fileManager.copyItem(at: source, to: target)
                return .copied(target)
            } catch {
                throw SourceFileActionError.failed(action: action, reason: error.localizedDescription)
            }

        case .trash:
            do {
                try fileManager.trashItem(at: source, resultingItemURL: nil)
                return .trashed
            } catch {
                throw SourceFileActionError.failed(action: action, reason: error.localizedDescription)
            }

        case .delete:
            do {
                try fileManager.removeItem(at: source)
                return .deleted
            } catch {
                throw SourceFileActionError.failed(action: action, reason: error.localizedDescription)
            }
        }
    }
}
