import Foundation

/// The deterministic environment the XCUITest suite launches into
/// (Tests/ImageKidSlicerUITests). Both arguments are inert in normal runs:
///
/// - `--uitest-open <path>` loads that image at launch, bypassing
///   `NSOpenPanel` (which XCUITest cannot script reliably). It may be
///   repeated, which is how a test stands up a filmstrip of several images.
/// - `--uitest-save <name>` makes Save write straight into a folder of that
///   name inside the app's own temporary directory, instead of asking for
///   one. It is a name rather than a path on purpose: under XCUITest the
///   runner and the app have separate sandbox containers, and the app may
///   read the runner's fixtures but not write into them — only the app can
///   pick somewhere it is allowed to write.
enum UITestMode {
    static var openPath: String? { openPaths.first }

    /// Every `--uitest-open <path>`, in the order given.
    static var openPaths: [String] { values(after: "--uitest-open") }
    static var savePath: String? { value(after: "--uitest-save") }

    static var enabled: Bool { openPath != nil || savePath != nil }

    /// The folder Save should use without prompting, when the suite set one.
    /// Created on demand inside the app's own sandbox container.
    static var saveFolder: URL? {
        guard let savePath else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(savePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The images to open at launch, when the suite set any.
    static var openURLs: [URL] { openPaths.map { URL(fileURLWithPath: $0) } }

    private static func value(after flag: String) -> String? {
        values(after: flag).first
    }

    private static func values(after flag: String) -> [String] {
        values(after: flag, in: CommandLine.arguments)
    }

    /// Split out from `CommandLine.arguments` so the parsing is testable — a
    /// repeated flag that silently yields one value instead of two is
    /// invisible until a journey fails for the wrong reason.
    static func values(after flag: String, in arguments: [String]) -> [String] {
        arguments.indices.compactMap { index in
            guard arguments[index] == flag, arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
    }
}
