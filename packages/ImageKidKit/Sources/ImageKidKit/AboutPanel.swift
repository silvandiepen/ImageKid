import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

/// The shared About window for ImageKid and Fekthor — same layout in both,
/// differing only in name, icon, tagline and links.
///
/// Present it from the app's `About …` menu item by replacing the default
/// `orderFrontStandardAboutPanel(_:)` with `AboutWindow.show(...)`.
public struct AboutPanelInfo {
    public let name: String
    public let tagline: String
    public let icon: Image?
    public let accent: Color
    public let links: [HomeLink]
    public let credit: String?

    public init(
        name: String,
        tagline: String,
        icon: Image?,
        accent: Color,
        links: [HomeLink] = [],
        credit: String? = nil
    ) {
        self.name = name
        self.tagline = tagline
        self.icon = icon
        self.accent = accent
        self.links = links
        self.credit = credit
    }

    /// `CFBundleShortVersionString (CFBundleVersion)`, read from the main bundle.
    public var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        guard let build, build != short else { return "Version \(short)" }
        return "Version \(short) (\(build))"
    }

    public var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }
}

public struct AboutPanel: View {
    private let info: AboutPanelInfo

    public init(info: AboutPanelInfo) {
        self.info = info
    }

    public var body: some View {
        ZStack {
            HomeBackground(opacity: 0.85)

            VStack(spacing: 0) {
                if let icon = info.icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
                        .padding(.bottom, 16)
                }

                Text(info.name)
                    .font(.figtree(size: 30, weight: .black))
                    .foregroundStyle(.white)

                Text(info.tagline)
                    .font(.figtree(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                Text(info.versionText)
                    .font(.figtree(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .textSelection(.enabled)
                    .padding(.top, 14)

                if !info.links.isEmpty {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 12),
                            count: min(info.links.count, 3)
                        ),
                        spacing: 8
                    ) {
                        ForEach(info.links) { link in
                            Button(link.title, action: link.action)
                                .buttonStyle(.plain)
                                .font(.figtree(size: 12, weight: .semibold))
                                .foregroundStyle(info.accent)
                        }
                    }
                    .padding(.top, 16)
                }

                Spacer(minLength: 14)

                VStack(spacing: 3) {
                    if let credit = info.credit {
                        Text(credit)
                            .font(.figtree(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    if !info.copyright.isEmpty {
                        Text(info.copyright)
                            .font(.figtree(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 34)
            .padding(.top, 38)
            .padding(.bottom, 22)
        }
        .frame(width: 360, height: 366)
    }
}

#if canImport(AppKit)
    /// Hosts `AboutPanel` in a single reusable window.
    @MainActor
    public enum AboutWindow {
        private static var window: NSWindow?

        public static func show(_ info: AboutPanelInfo) {
            Typography.register()

            if let window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let hosting = NSHostingController(rootView: AboutPanel(info: info))
            let panel = NSWindow(contentViewController: hosting)
            panel.title = "About \(info.name)"
            panel.styleMask = [.titled, .closable, .fullSizeContentView]
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isMovableByWindowBackground = true
            panel.backgroundColor = .black
            panel.isReleasedWhenClosed = false
            panel.center()

            window = panel
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
#endif
