import Foundation

/// The deterministic environment the XCUITest suite launches into
/// (Tests/FekthorUITests). Three launch arguments, all inert in normal runs:
///
/// - `--uitest` swaps every persisted preference onto a fresh, wiped
///   defaults suite — default panel layout, no recent workspaces, no stored
///   palette anchors — so each test launch starts from first-run state
///   without ever touching the developer's real preferences.
/// - `--uitest-workspace <path>` opens that folder as a workspace straight
///   away, bypassing NSOpenPanel (which XCUITest cannot script reliably).
///   The tests put the folder inside the app container, which the sandbox
///   can always read.
/// - `--uitest-open <path>` routes that file through the normal open path
///   (editor for .svg/.fekthor) — the relaunch half of the save-flow test.
enum UITestMode {
    /// Any of the UI-test arguments is present: skip restoring state and
    /// the trace flow's bare-path launch argument.
    static let enabled =
        CommandLine.arguments.contains("--uitest")
        || workspacePath != nil || openPath != nil

    static let workspacePath = value(after: "--uitest-workspace")
    static let openPath = value(after: "--uitest-open")

    fileprivate static let suiteName = "com.hakobs.fekthor.uitest"

    private static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else {
            return nil
        }
        return args[i + 1]
    }
}

/// The defaults store every persisted preference goes through: `.standard`
/// normally, a wiped per-run suite under `--uitest` (see `UITestMode`).
enum AppDefaults {
    static let store: UserDefaults = {
        guard UITestMode.enabled,
            let suite = UserDefaults(suiteName: UITestMode.suiteName)
        else { return .standard }
        suite.removePersistentDomain(forName: UITestMode.suiteName)
        return suite
    }()
}
