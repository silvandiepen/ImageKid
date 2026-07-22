import Foundation

/// Runs a `Workfile.ExportProfile` — a named, ordered list of opaque action
/// strings (see `ExportAction` for the grammar) — over documents.
///
/// Non-destructive: the source `GraphicDocument` is never modified; every
/// action returns a new document. Deterministic: the same profile over the
/// same inputs yields identical results, and batch output is sorted by file
/// name.
public enum ExportRunner {
    /// Output naming template used when `profile.output` is nil.
    /// Supported placeholders: `{name}` (the artboard/document name) and
    /// `{profile}` (the profile name).
    public static let defaultOutputTemplate = "{name}.svg"

    /// Parse a profile's action strings into typed actions. Blank entries are
    /// skipped (forgiving); the first unknown/malformed action throws its
    /// typed `ExportActionError`.
    public static func actions(of profile: Workfile.ExportProfile) throws -> [ExportAction] {
        var out: [ExportAction] = []
        for raw in profile.actions ?? [] {
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            out.append(try ExportAction.parse(raw))
        }
        return out
    }

    /// The output file name for a document run through a profile.
    public static func fileName(profile: Workfile.ExportProfile, name: String) -> String {
        let template = profile.output ?? defaultOutputTemplate
        return template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{profile}", with: profile.name)
    }

    /// Apply a profile to one document. Returns the templated file name and
    /// the transformed document. Throws `ExportActionError` on bad actions.
    public static func apply(
        profile: Workfile.ExportProfile, to doc: GraphicDocument, name: String
    ) throws -> (fileName: String, document: GraphicDocument) {
        var out = doc
        for action in try actions(of: profile) {
            out = action.applied(to: out)
        }
        return (fileName(profile: profile, name: name), out)
    }

    /// Batch: apply a profile to every named document. Results are sorted by
    /// file name, so batch output order is deterministic regardless of the
    /// dictionary's iteration order.
    public static func run(
        profile: Workfile.ExportProfile, over documents: [String: GraphicDocument]
    ) throws -> [(fileName: String, document: GraphicDocument)] {
        var out: [(fileName: String, document: GraphicDocument)] = []
        out.reserveCapacity(documents.count)
        for name in documents.keys.sorted() {
            out.append(try apply(profile: profile, to: documents[name]!, name: name))
        }
        out.sort { $0.fileName < $1.fileName }
        return out
    }
}
