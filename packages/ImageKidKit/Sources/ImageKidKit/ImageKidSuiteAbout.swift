import SwiftUI

#if canImport(AppKit)
    import AppKit

    public enum ImageKidSuiteApp: String, CaseIterable {
        case imageKid
        case cutout
        case upscale
        case slicer

        public var name: String {
            switch self {
            case .imageKid: "ImageKid"
            case .cutout: "Cutout"
            case .upscale: "Upscale"
            case .slicer: "Slicer"
            }
        }

        fileprivate var bundleIdentifier: String {
            switch self {
            case .imageKid: "com.hakobs.imagekid"
            case .cutout: "com.hakobs.imagekid.cutout"
            case .upscale: "com.hakobs.imagekid.upscale"
            case .slicer: "com.hakobs.imagekid.slicer"
            }
        }

        fileprivate var tagline: String {
            switch self {
            case .imageKid: "View, edit, and transform images locally on your Mac."
            case .cutout: "Remove backgrounds from batches of images, entirely on your Mac."
            case .upscale: "Make batches of images larger while preserving detail."
            case .slicer: "Turn image sheets into clean, reusable slices."
            }
        }
    }

    /// Produces a consistent About panel with shortcuts to every other ImageKid app.
    public enum ImageKidSuiteAbout {
        public static func info(for app: ImageKidSuiteApp) -> AboutPanelInfo {
            AboutPanelInfo(
                name: app.name,
                tagline: app.tagline,
                icon: NSImage(named: NSImage.applicationIconName).map { Image(nsImage: $0) },
                accent: .accentColor,
                links: links(excluding: app)
            )
        }

        public static func links(excluding current: ImageKidSuiteApp) -> [HomeLink] {
            ImageKidSuiteApp.allCases.compactMap { app in
                guard app != current else { return nil }
                return HomeLink(id: "suite.\(app.rawValue)", title: app.name) {
                    open(app)
                }
            }
        }

        private static func open(_ app: ImageKidSuiteApp) {
            let workspace = NSWorkspace.shared
            if let installedURL = workspace.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
                workspace.openApplication(at: installedURL, configuration: .init())
                return
            }
            workspace.open(URL(string: "https://imagekid.hakobs.com")!)
        }
    }
#endif
