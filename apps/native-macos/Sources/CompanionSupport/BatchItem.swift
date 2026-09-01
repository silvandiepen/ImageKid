import AppKit
import Foundation

struct BatchItem: Identifiable, Equatable {
    enum State: Equatable {
        case waiting
        case processing(String, Double?)
        case done(URL)
        case skipped
        case failed(String)
    }

    let id = UUID()
    /// Where the input file is *now*. A When Done action can move it, and the row's
    /// Open / Show in Finder have to keep pointing at a file that still exists.
    var sourceURL: URL
    /// Where the file was when it joined the queue. A When Done action rewrites
    /// `sourceURL`, so this is what stops the same file being queued a second time
    /// under its original path and processed against a file that has since moved.
    let originalSourceURL: URL
    var thumbnail: NSImage?
    /// Preview of the produced file, loaded once the item finishes. Replaces the
    /// source thumbnail in the queue so a row shows what was actually made.
    var outputThumbnail: NSImage?
    var pixelSize: CGSize?
    var state: State = .waiting
    /// Where the next run would write this item, and whether that file is already there.
    /// Recomputed whenever the queue, the destination or the operation changes.
    var plannedOutputURL: URL?
    var hasExistingResult = false
    /// What the When Done action did with the input file, or why it could not.
    var sourceActionNote: String?
    var sourceActionFailed = false

    var fileName: String {
        sourceURL.lastPathComponent
    }

    var sizeLabel: String {
        guard let pixelSize else { return "Unknown size" }
        return "\(Int(pixelSize.width)) x \(Int(pixelSize.height)) px"
    }

    var outputURL: URL? {
        guard case .done(let url) = state else { return nil }
        return url
    }

    var isDone: Bool {
        outputURL != nil
    }

    var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    /// True when a run would land on a file that is already on disk — either one this
    /// session produced, or one left by an earlier run.
    var wouldOverwriteExistingFile: Bool {
        isDone || hasExistingResult
    }

    /// The file this row's actions (open, reveal) should target.
    var actionableURL: URL {
        outputURL ?? sourceURL
    }

    var previewImage: NSImage? {
        outputThumbnail ?? thumbnail
    }

    static func == (lhs: BatchItem, rhs: BatchItem) -> Bool {
        lhs.id == rhs.id
    }
}
