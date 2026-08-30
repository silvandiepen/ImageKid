import Foundation

/// Launch-argument hooks for driving the app without a person at the keyboard.
///
/// The macOS counterpart of the iOS `UITestSupport`. Sculptor's one expensive
/// action lives behind a button, and synthesising a click into it needs
/// Accessibility permission that a build machine — or anyone working remotely —
/// will not have. Without a hook, the whole path from button to preview can
/// only ever be verified by hand.
///
///     ImageKid\ Sculptor --auto-generate <image>
///
/// `--auto-generate` opens the image and starts a generation as though the
/// button had been pressed, so screenshots and UI tests can reach the
/// processing and result states. It changes nothing about how a generation
/// runs; it only presses the button.
enum AutomationSupport {
    /// Start a generation as soon as an image is open.
    static var autoGenerates: Bool {
        CommandLine.arguments.contains("--auto-generate")
    }

    /// Open the export sheet once a result is on screen, for capturing it.
    static var showsExportSheet: Bool {
        CommandLine.arguments.contains("--show-export")
    }

    /// An image path given directly on the command line.
    ///
    /// `open -a` delivers files through the app delegate, but a binary launched
    /// straight from a shell gets them as arguments, which is how an automated
    /// run starts the app.
    static var imageArgument: URL? {
        let arguments = CommandLine.arguments.dropFirst()
        for argument in arguments where !argument.hasPrefix("-") {
            let url = URL(fileURLWithPath: argument)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static var isActive: Bool {
        autoGenerates || showsExportSheet || imageArgument != nil
    }
}
