import AppKit
import ImageKidKit
import ImageIO
import SwiftUI

/// ImageKid's home screen. The layout lives in `HomeScreen` (ImageKidKit) and
/// is shared with Fekthor — only the copy, cards, accent and character differ.
struct EmptyStateView: View {
    let isDropTarget: Bool
    let openAction: () -> Void
    var newAction: () -> Void = {}
    var openURLAction: (URL) -> Void = { _ in }

    @StateObject private var thumbnails = RecentThumbnailStore()

    private static let accent = Color(red: 0.34, green: 0.66, blue: 0.96)

    var body: some View {
        HomeScreen(
            title: isDropTarget ? "Drop it right here!" : "ImageKid",
            subtitle: "Remove backgrounds, upscale, edit with AI.",
            footnote: "or drop an image anywhere · ⌘V to paste",
            character: ImageKidAsset.image(named: "ImageKidCharacter").map { Image(nsImage: $0) },
            characterAspect: 1128.0 / 2048.0,
            accent: Self.accent,
            actions: [
                HomeAction(
                    id: "home.openImage",
                    icon: isDropTarget ? "tray.and.arrow.down.fill" : "photo.badge.plus.fill",
                    title: isDropTarget ? "Release to open" : "Open Image",
                    subtitle: "JPG, PNG, WebP",
                    action: openAction
                ),
                HomeAction(
                    id: "home.newCanvas",
                    icon: "doc.badge.plus",
                    title: "New Canvas",
                    subtitle: "Start blank",
                    action: newAction
                )
            ],
            highlighted: isDropTarget,
            recents: { recentFiles }
        )
    }

    /// Recently opened images, from the documents the app already registers
    /// via `noteNewRecentDocumentURL`.
    @ViewBuilder
    private var recentFiles: some View {
        let recents = Array(NSDocumentController.shared.recentDocumentURLs.prefix(3))

        if !recents.isEmpty {
            HomeRecentsSection {
                ForEach(recents, id: \.self) { url in
                    HomeRecentRow(
                        title: url.deletingPathExtension().lastPathComponent,
                        detail: detail(for: url),
                        help: url.path,
                        action: { openURLAction(url) },
                        accessory: {
                            ZStack {
                                Rectangle().fill(Color.white.opacity(0.07))
                                if let image = thumbnails.thumbnail(for: url) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "photo")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                            }
                        }
                    )
                    .task(id: url) { thumbnails.request(url) }
                }
            }
        }
    }

    private func detail(for url: URL) -> String {
        let folder = url.deletingLastPathComponent().path
        return (folder as NSString).abbreviatingWithTildeInPath
    }
}

/// Small on-demand thumbnail cache for the recents list. Uses ImageIO so a
/// 50 MP source is decoded straight to a 68px thumb, never in full.
@MainActor
final class RecentThumbnailStore: ObservableObject {
    @Published private var cache: [URL: NSImage] = [:]
    private var inFlight: Set<URL> = []

    func thumbnail(for url: URL) -> NSImage? { cache[url] }

    func request(_ url: URL) {
        guard cache[url] == nil, !inFlight.contains(url) else { return }
        inFlight.insert(url)

        Task.detached(priority: .utility) {
            let image = Self.makeThumbnail(url: url, maxPixel: 68)
            await MainActor.run {
                self.inFlight.remove(url)
                if let image { self.cache[url] = image }
            }
        }
    }

    nonisolated private static func makeThumbnail(url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

extension AboutPanelInfo {
    /// ImageKid's About window contents. Fekthor has the mirror of this.
    static var imageKid: AboutPanelInfo {
        AboutPanelInfo(
            name: "ImageKid",
            tagline: "Remove backgrounds, upscale, edit with AI.\nOn your Mac, on your images.",
            // The real bundle icon, not the stale ImageKidAppIcon.png asset.
            icon: NSImage(named: NSImage.applicationIconName).map { Image(nsImage: $0) },
            accent: Color(red: 0.34, green: 0.66, blue: 0.96),
            links: [
                HomeLink(id: "about.site", title: "Website") {
                    NSWorkspace.shared.open(URL(string: "https://imagekid.app")!)
                },
                HomeLink(id: "about.notices", title: "Acknowledgements") {
                    NSWorkspace.shared.open(URL(string: "https://imagekid.app/acknowledgements")!)
                }
            ] + ImageKidSuiteAbout.links(excluding: .imageKid)
        )
    }
}
