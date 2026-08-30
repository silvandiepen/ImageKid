import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// A saved slicing session: which images were open, and everything drawn on
/// each of them.
///
/// This is the one place Slicer has a document format. It is deliberately
/// plain JSON describing *layout*, not pixels — reopening one re-reads the
/// original sources, so a session file stays tiny and never becomes a second
/// copy of the user's images.
struct SlicerSessionDocument: Codable, Equatable {
    /// Bumped only when an older file could not be read as-is.
    static let currentVersion = 1
    static let fileExtension = "slicer"
    static let contentType = UTType(
        exportedAs: "com.hakobs.imagekid.slicer.session",
        conformingTo: .data
    )

    var version = currentVersion
    var images: [Image] = []
    var grid = SliceGrid()
    var isSnappingEnabled = true
    var snapsToCentreLines = true
    var exportOptions = ExportOptions()

    struct Image: Codable, Equatable {
        var displayName: String
        /// The path is a human-readable fallback and a debugging aid; the
        /// bookmark is what actually survives the sandbox and a moved file.
        var path: String?
        var bookmark: Data?
        var slices: [Slice] = []
        var guides: [Guide] = []
        var cropRect: Rect?
    }

    /// Slices and guides are stored structurally rather than by reusing the
    /// runtime types, so a refactor of those cannot silently change the file
    /// format under an existing session.
    struct Slice: Codable, Equatable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
        var name: String?
        var isLocked: Bool = false
    }

    struct Guide: Codable, Equatable {
        var isVertical: Bool
        var position: CGFloat
    }

    struct Rect: Codable, Equatable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }
}

// MARK: - Converting to and from the running session

extension SlicerSessionDocument.Slice {
    init(_ slice: Slice) {
        self.init(
            x: slice.rect.minX,
            y: slice.rect.minY,
            width: slice.rect.width,
            height: slice.rect.height,
            name: slice.name,
            isLocked: slice.isLocked
        )
    }

    var restored: Slice {
        Slice(
            rect: SliceGeometry.clamped(CGRect(x: x, y: y, width: width, height: height)),
            name: name,
            isLocked: isLocked
        )
    }
}

extension SlicerSessionDocument.Guide {
    init(_ guide: SliceGuide) {
        self.init(isVertical: guide.axis == .vertical, position: guide.position)
    }

    var restored: SliceGuide {
        SliceGuide(axis: isVertical ? .vertical : .horizontal, position: position)
    }
}

extension SlicerSessionDocument.Rect {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    var restored: CGRect {
        SliceGeometry.clamped(CGRect(x: x, y: y, width: width, height: height))
    }
}

extension SlicerSessionDocument {
    /// A security-scoped bookmark, so a sandboxed relaunch can still reach the
    /// file. Making one needs current access, which the open panel granted.
    static func bookmark(for url: URL?) -> Data? {
        guard let url else { return nil }
        return try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolve a stored image back to a file, preferring the bookmark and
    /// falling back to the recorded path.
    ///
    /// Returns whether security scope was started, so the caller can balance
    /// it — an unbalanced start leaks the scope for the life of the process.
    static func resolve(_ image: Image) -> (url: URL, startedScope: Bool)? {
        if let bookmark = image.bookmark {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return (url, url.startAccessingSecurityScopedResource())
            }
        }
        guard let path = image.path else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? (url, false) : nil
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> SlicerSessionDocument {
        let document = try JSONDecoder().decode(SlicerSessionDocument.self, from: data)
        guard document.version <= currentVersion else {
            throw SliceError.unreadableSession
        }
        return document
    }
}
