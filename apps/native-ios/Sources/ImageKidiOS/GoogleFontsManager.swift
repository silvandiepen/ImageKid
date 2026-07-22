import CoreText
import Foundation
import SwiftUI

/// A Google Font the user has downloaded and registered on the device.
struct InstalledGoogleFont: Codable, Identifiable, Equatable {
    var id: String { family }
    let family: String
    let postScriptName: String
    let fileName: String
}

/// Downloads Google Fonts on demand and registers them with the system so they
/// can be used like any built-in font — nothing is bundled in the app, and each
/// font is only fetched when the user taps to install it. Installed fonts are
/// cached in Application Support and re-registered on launch.
@MainActor
final class GoogleFontsManager: ObservableObject {
    @Published private(set) var installed: [InstalledGoogleFont] = []
    @Published private(set) var installing: Set<String> = []
    @Published var errorMessage: String?

    /// A curated set of popular Google Fonts (no API key needed — each is fetched
    /// on demand via the Google Fonts CSS endpoint).
    let curated: [String] = [
        "Montserrat", "Poppins", "Roboto", "Open Sans", "Lato", "Inter", "Work Sans",
        "Raleway", "Nunito", "Quicksand", "Oswald", "Bebas Neue", "Anton", "Archivo",
        "Josefin Sans", "Comfortaa", "Righteous", "Merriweather", "Playfair Display",
        "DM Serif Display", "Abril Fatface", "Cinzel", "Lobster", "Pacifico",
        "Dancing Script", "Caveat", "Satisfy", "Sacramento", "Permanent Marker",
        "Shadows Into Light", "Amatic SC", "Kalam"
    ]

    init() {
        load()
        registerAll()
    }

    func isInstalled(_ family: String) -> Bool { installed.contains { $0.family == family } }
    func isInstalling(_ family: String) -> Bool { installing.contains(family) }

    /// Font choices (label, PostScript name) for everything the user has installed.
    var installedChoices: [(name: String, psName: String?)] {
        installed.map { ($0.family, $0.postScriptName) }
    }

    func install(_ family: String) async {
        guard !isInstalled(family), !installing.contains(family) else { return }
        installing.insert(family)
        defer { installing.remove(family) }
        do {
            let ttfURL = try await fetchTTFURL(for: family)
            let (data, _) = try await URLSession.shared.data(from: ttfURL)
            let fileName = family.replacingOccurrences(of: " ", with: "-") + ".ttf"
            let dest = fontsDirectory.appendingPathComponent(fileName)
            try data.write(to: dest, options: .atomic)
            guard let psName = registerFont(at: dest) else {
                try? FileManager.default.removeItem(at: dest)
                throw FontError.registerFailed
            }
            let font = InstalledGoogleFont(family: family, postScriptName: psName, fileName: fileName)
            installed.removeAll { $0.family == family }
            installed.append(font)
            installed.sort { $0.family < $1.family }
            save()
        } catch {
            errorMessage = "Couldn't install “\(family)”. Check your connection and try again."
        }
    }

    func remove(_ font: InstalledGoogleFont) {
        let url = fontsDirectory.appendingPathComponent(font.fileName)
        var err: Unmanaged<CFError>?
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &err)
        try? FileManager.default.removeItem(at: url)
        installed.removeAll { $0.id == font.id }
        save()
    }

    // MARK: - Networking

    /// Ask Google Fonts for the family's CSS and pull out a .ttf source URL. An
    /// old User-Agent makes Google serve TrueType (which CoreText can register)
    /// instead of woff2 (which it can't).
    private func fetchTTFURL(for family: String) async throws -> URL {
        let query = family.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? family
        guard let cssURL = URL(string: "https://fonts.googleapis.com/css?family=\(query)") else {
            throw FontError.badURL
        }
        var request = URLRequest(url: cssURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 6_0 like Mac OS X) AppleWebKit/536.26",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, _) = try await URLSession.shared.data(for: request)
        let css = String(decoding: data, as: UTF8.self)
        guard let url = Self.firstTTFURL(in: css) else { throw FontError.noTTF }
        return url
    }

    static func firstTTFURL(in css: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: #"url\((https://[^)]+?\.ttf)\)"#) else { return nil }
        let range = NSRange(css.startIndex..., in: css)
        guard let match = regex.firstMatch(in: css, range: range),
              let urlRange = Range(match.range(at: 1), in: css) else { return nil }
        return URL(string: String(css[urlRange]))
    }

    // MARK: - Registration & storage

    /// Register a font file and return its PostScript name (used to reference it).
    private func registerFont(at url: URL) -> String? {
        var err: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first else { return nil }
        let ctFont = CTFontCreateWithFontDescriptor(first, 0, nil)
        return CTFontCopyPostScriptName(ctFont) as String
    }

    private func registerAll() {
        for font in installed {
            let url = fontsDirectory.appendingPathComponent(font.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var err: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err)
        }
    }

    private var fontsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("GoogleFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var storeURL: URL { fontsDirectory.appendingPathComponent("installed.json") }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let list = try? JSONDecoder().decode([InstalledGoogleFont].self, from: data) else { return }
        installed = list
    }

    private func save() {
        try? JSONEncoder().encode(installed).write(to: storeURL, options: .atomic)
    }

    enum FontError: Error { case badURL, noTTF, registerFailed }
}
