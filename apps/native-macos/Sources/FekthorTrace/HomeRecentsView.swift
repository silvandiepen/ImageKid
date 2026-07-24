import AppKit
import FekthorKit
import ImageKidKit
import SwiftUI

/// Loads home-screen previews for recent workspaces: a handful of icon
/// thumbnails plus category/icon counts, read quietly through the recent's
/// security-scoped bookmark (never prompting — access failures just fall
/// back to a folder glyph).
@MainActor
final class RecentPreviewStore: ObservableObject {
    struct Preview {
        var thumbnails: [NSImage]
        var iconCount: Int
        var categoryCount: Int
    }

    @Published private(set) var previews: [String: Preview] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []

    func preview(for recent: RecentWorkspace) -> Preview? {
        previews[recent.path]
    }

    func request(_ recent: RecentWorkspace) {
        let key = recent.path
        guard previews[key] == nil, !inFlight.contains(key), !failed.contains(key) else {
            return
        }
        inFlight.insert(key)
        let bookmark = recent.bookmark
        Task.detached(priority: .utility) {
            let loaded = Self.load(bookmark: bookmark, path: key)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlight.remove(key)
                if let loaded {
                    self.previews[key] = loaded
                } else {
                    self.failed.insert(key)
                }
            }
        }
    }

    private nonisolated static func load(bookmark: Data?, path: String) -> Preview? {
        var url = URL(fileURLWithPath: path)
        var scoped = false
        if let bookmark {
            var stale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                relativeTo: nil, bookmarkDataIsStale: &stale)
            {
                url = resolved
                scoped = url.startAccessingSecurityScopedResource()
            }
        }
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let ws = try? Workspace.scan(url) else { return nil }
        var thumbs: [NSImage] = []
        for entry in ws.entries {
            if thumbs.count == 4 { break }
            guard let data = try? Data(contentsOf: entry.url),
                let doc = try? SVGReader.read(data),
                let cg = ThumbnailRenderer.render(doc, pixelSize: 64)
            else { continue }
            thumbs.append(NSImage(cgImage: cg, size: NSSize(width: 32, height: 32)))
        }
        return Preview(
            thumbnails: thumbs, iconCount: ws.entries.count,
            categoryCount: ws.categories.count)
    }
}

/// One recent-workspace row on the home screen: a 2×2 mini-grid of icon
/// thumbnails (or a folder glyph while loading / when access fails), the
/// workspace name, and its counts.
struct RecentWorkspaceRow: View {
    let recent: RecentWorkspace
    @ObservedObject var store: RecentPreviewStore
    var action: () -> Void

    var body: some View {
        HomeRecentRow(
            title: recent.name,
            detail: subtitle,
            help: recent.path,
            action: action,
            accessory: { previewGrid }
        )
        .task(id: recent.path) { store.request(recent) }
    }

    private var subtitle: String {
        guard let preview = store.preview(for: recent) else {
            return (recent.path as NSString).abbreviatingWithTildeInPath
        }
        let icons = "\(preview.iconCount) icon\(preview.iconCount == 1 ? "" : "s")"
        guard preview.categoryCount > 0 else { return icons }
        let cats =
            "\(preview.categoryCount) categor\(preview.categoryCount == 1 ? "y" : "ies")"
        return "\(cats) \u{00B7} \(icons)"
    }

    @ViewBuilder
    private var previewGrid: some View {
        let thumbs = store.preview(for: recent)?.thumbnails ?? []
        ZStack {
            Rectangle().fill(Color.white.opacity(0.07))
            if thumbs.isEmpty {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            } else {
                let columns = [
                    GridItem(.fixed(13), spacing: 2), GridItem(.fixed(13), spacing: 2),
                ]
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(thumbs.prefix(4).enumerated()), id: \.offset) { _, image in
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                    }
                }
            }
        }
    }
}
