import AppKit
import SwiftUI

@main
struct ImageKidSlicerApp: App {
    @StateObject private var model = SlicerDocumentModel()
    @NSApplicationDelegateAdaptor(SlicerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            SlicerWindow(model: model)
                .onAppear {
                    appDelegate.model = model
                    model.load(urls: UITestMode.openURLs)
                }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            SlicerCommands(model: model)
        }
    }
}

/// Opening a file from the Dock or Finder, and the close protection the doc
/// asks for: quitting with unsaved slices has to ask first.
final class SlicerAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: SlicerDocumentModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Slicer is a dark tool: judging a crop against a light chrome is
        // harder, and the app has no appearance setting to honour.
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model else { return }
        Task { @MainActor in model.load(urls: urls) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        return MainActor.assumeIsolated {
            model.confirmDiscardingSlices(actionTitle: "Quit") ? .terminateNow : .terminateCancel
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
