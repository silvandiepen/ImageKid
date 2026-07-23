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

    /// Why `safeFileName` rejected a templated output name.
    public enum FileNameError: Error, Equatable, Sendable, CustomStringConvertible {
        /// Nothing left after normalization (empty, only slashes/`.`, or a
        /// `..` chain that lands exactly on the destination).
        case empty
        /// The name climbs above the destination directory (`../…`).
        case escapesDestination(String)

        public var description: String {
            switch self {
            case .empty:
                return "output name is empty"
            case .escapesDestination(let name):
                return "output name \"\(name)\" escapes the destination folder"
            }
        }
    }

    /// Normalize a templated output name into a relative path guaranteed to
    /// stay STRICTLY inside the destination directory. Templates are user
    /// data (`{name}`/`{profile}` substitution), so a name like
    /// `../../etc/x.svg` or `/abs/x.svg` must never leave the folder the
    /// user picked. Leading slashes are stripped (absolute → relative),
    /// empty and `.` components collapse, and `..` resolves lexically — a
    /// name that would climb out throws `FileNameError.escapesDestination`;
    /// one that resolves to nothing throws `FileNameError.empty`.
    public static func safeFileName(_ fileName: String) throws -> String {
        var components: [Substring] = []
        // `split` drops empty runs, which strips leading/doubled slashes.
        for part in fileName.split(separator: "/") {
            switch part {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else {
                    throw FileNameError.escapesDestination(fileName)
                }
                components.removeLast()
            default:
                components.append(part)
            }
        }
        guard !components.isEmpty else { throw FileNameError.empty }
        return components.joined(separator: "/")
    }

    /// Apply a profile to one document. Returns the templated file name and
    /// the transformed document. Throws `ExportActionError` on bad actions.
    ///
    /// `namedStyles` are the workspace's graphic styles: their binding
    /// classes are FLATTENED away before the actions run (values are inline
    /// already) unless a style opts in with `exportClass: true`. User
    /// classes always pass through. Pass `[]` (the default) to skip.
    public static func apply(
        profile: Workfile.ExportProfile, to doc: GraphicDocument, name: String,
        namedStyles: [NamedStyle] = []
    ) throws -> (fileName: String, document: GraphicDocument) {
        // Editor metadata (file-local swatches/styles) is an authoring aid;
        // deliverables never carry it.
        var out = FileMeta.removing(from: doc)
        out = NamedStyles.strippingStyleClasses(out, styles: namedStyles)
        for action in try actions(of: profile) {
            out = action.applied(to: out)
        }
        return (fileName(profile: profile, name: name), out)
    }

    /// Batch: apply a profile to every named document. Results are sorted by
    /// file name, so batch output order is deterministic regardless of the
    /// dictionary's iteration order.
    public static func run(
        profile: Workfile.ExportProfile, over documents: [String: GraphicDocument],
        namedStyles: [NamedStyle] = []
    ) throws -> [(fileName: String, document: GraphicDocument)] {
        var out: [(fileName: String, document: GraphicDocument)] = []
        out.reserveCapacity(documents.count)
        for name in documents.keys.sorted() {
            out.append(
                try apply(
                    profile: profile, to: documents[name]!, name: name,
                    namedStyles: namedStyles))
        }
        out.sort { $0.fileName < $1.fileName }
        return out
    }
}
