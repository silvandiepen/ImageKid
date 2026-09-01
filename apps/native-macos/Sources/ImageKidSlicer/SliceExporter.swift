import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Everything one Save needs. The full-resolution image travels with the
/// request so the export can run off the main actor without reaching back into
/// the document model.
struct SliceExportRequest {
    let sourceName: String
    let image: CGImage
    /// The source's own type and extension; `options` decides what is written.
    let sourceType: UTType
    let sourceExtension: String
    let slices: [Slice]
    let folder: URL
    var options = ExportOptions()

    var output: (type: UTType, fileExtension: String) {
        options.resolved(sourceType: sourceType, sourceExtension: sourceExtension)
    }

    var quality: Double? {
        options.isLossy(sourceType: sourceType) ? options.quality : nil
    }
}

/// What a Save produced. Failures are collected rather than thrown so one bad
/// slice cannot cost the user the other nine.
struct SliceExportOutcome {
    var created: [URL] = []
    var failures: [Failure] = []

    struct Failure {
        let sliceName: String
        let message: String
    }

    var isCompleteSuccess: Bool { failures.isEmpty && !created.isEmpty }
}

enum SliceExporter {
    /// Crop and write every slice, in order, at source resolution.
    ///
    /// Serial by design: a sheet can be very large, and one crop in flight at a
    /// time keeps peak memory to the source plus a single slice.
    static func export(_ request: SliceExportRequest) -> SliceExportOutcome {
        var outcome = SliceExportOutcome()
        var claimed = Set<String>()

        let pixelSize = CGSize(width: request.image.width, height: request.image.height)
        let count = request.slices.count
        let output = request.output
        let quality = request.quality

        for (index, slice) in request.slices.enumerated() {
            let displayName = slice.displayName(at: index)
            let baseName = fileName(
                sourceName: request.sourceName,
                index: index,
                count: count,
                customName: slice.name,
                prefix: request.options.sanitizedPrefix
            )

            guard let pixelRect = SliceGeometry.pixelRect(slice.rect, pixelSize: pixelSize) else {
                outcome.failures.append(.init(
                    sliceName: displayName,
                    message: SliceError.emptySlice.localizedDescription
                ))
                continue
            }

            guard let cropped = request.image.cropping(to: pixelRect) else {
                outcome.failures.append(.init(
                    sliceName: displayName,
                    message: SliceError.emptySlice.localizedDescription
                ))
                continue
            }

            let url = uniqueURL(
                in: request.folder,
                baseName: baseName,
                fileExtension: output.fileExtension,
                claimed: claimed
            )
            claimed.insert(url.path)

            do {
                let resampled = try SliceImageIO.rendered(cropped, options: request.options)
                try SliceImageIO.writeAtomically(resampled, to: url, type: output.type, quality: quality)
                outcome.created.append(url)
            } catch {
                outcome.failures.append(.init(
                    sliceName: displayName,
                    message: error.localizedDescription
                ))
            }
        }

        return outcome
    }

    /// Crop one region out of the source and write it to an exact path — the
    /// Crop tool's whole job. Unlike a slice run this has one output, so a
    /// failure is worth throwing rather than collecting.
    static func exportCrop(
        _ image: CGImage,
        rect: CGRect,
        outputType: UTType,
        options: ExportOptions = ExportOptions(),
        quality: Double? = nil,
        to url: URL
    ) throws {
        let pixelSize = CGSize(width: image.width, height: image.height)
        guard
            let pixelRect = SliceGeometry.pixelRect(rect, pixelSize: pixelSize),
            let cropped = image.cropping(to: pixelRect)
        else {
            throw SliceError.emptySlice
        }
        let resampled = try SliceImageIO.rendered(cropped, options: options)
        try SliceImageIO.writeAtomically(resampled, to: url, type: outputType, quality: quality)
    }

    // MARK: - Naming

    /// `sheet-slice-01`, or a sanitised custom name in place of `slice-01`.
    /// Numbers are zero-padded to the width of the slice count so Finder keeps
    /// the export in creation order.
    static func fileName(
        sourceName: String,
        index: Int,
        count: Int,
        customName: String?,
        prefix: String = ""
    ) -> String {
        if let custom = sanitized(customName) {
            return prefix + custom
        }
        let width = max(2, String(max(count, 1)).count)
        let number = String(format: "%0\(width)d", index + 1)
        let base = sanitized(sourceName) ?? "image"
        return "\(prefix)\(base)-slice-\(number)"
    }

    /// A filename-safe version of a user-supplied name, or `nil` if nothing
    /// usable survives.
    static func sanitized(_ name: String?) -> String? {
        guard let name else { return nil }
        let stripped = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    /// Never overwrite: an existing (or already-claimed) path gets `-2`, `-3`,
    /// and so on appended before the extension.
    static func uniqueURL(
        in folder: URL,
        baseName: String,
        fileExtension: String,
        claimed: Set<String> = []
    ) -> URL {
        var candidate = folder.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) || claimed.contains(candidate.path) {
            candidate = folder
                .appendingPathComponent("\(baseName)-\(counter)")
                .appendingPathExtension(fileExtension)
            counter += 1
        }
        return candidate
    }
}
