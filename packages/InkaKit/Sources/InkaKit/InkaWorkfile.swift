import BrushKit
import Foundation

/// The `.inka` workfile codec: the whole document as one versioned JSON file
/// (raster/imported pixels embedded as base64 PNG inside `PNGImage`). Local and
/// self-contained — no sidecar files, matching the family's local-first stance.
public enum InkaWorkfile {
    public static let formatVersion = 1

    public static func encode(_ document: InkaDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(version: formatVersion, document: document))
    }

    public static func decode(_ data: Data) throws -> InkaDocument {
        var doc = try JSONDecoder().decode(Envelope.self, from: data).document
        // Make sure every built-in brush a stroke might reference is present,
        // so an old file still resolves after the library grows.
        for builtin in BrushLibrary.all where !doc.brushes.contains(where: { $0.id == builtin.id }) {
            doc.brushes.append(builtin)
        }
        return doc
    }

    private struct Envelope: Codable {
        var version: Int
        var document: InkaDocument
    }
}
