import AppKit
import ImageKidKit
import SwiftUI

@main
struct ImageKidSlicerApp: App {
    @StateObject private var model = SlicerDocumentModel()
    @NSApplicationDelegateAdaptor(SlicerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            SlicerWindow(model: model)
                .onAppear {
                    appDelegate.attach(model)
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
    private var pendingOpenURLs: [URL] = []

    private var menuObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Slicer is a dark tool: judging a crop against a light chrome is
        // harder, and the app has no appearance setting to honour.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Menu tooltips are annotated as each menu opens, because SwiftUI
        // rebuilds the items as state changes and titles flip with it.
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                guard let menu = NSApp.mainMenu else { return }
                SlicerHelp.applyTooltips(to: menu)
            }
        }
    }

    deinit {
        if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        open(urls, with: model)
    }

    func attach(_ model: SlicerDocumentModel) {
        self.model = model
        guard !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        open(urls, with: model)
    }

    private func open(_ urls: [URL], with model: SlicerDocumentModel) {
        let sessions = urls.filter { $0.pathExtension == SlicerSessionDocument.fileExtension }
        let images = urls.filter { $0.pathExtension != SlicerSessionDocument.fileExtension }
        Task { @MainActor in
            if let session = sessions.first { model.openSession(at: session) }
            model.load(urls: images)
        }
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
