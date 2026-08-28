import AppKit
import ImageKidSculptorKit
import SwiftUI

/// Receives files opened from Finder, the Dock, or `open -a`.
///
/// SwiftUI has no macOS hook for this on a plain `WindowGroup`, so it goes
/// through the classic delegate. Sculptor takes one image at a time, so extra
/// files in a multi-file open are ignored rather than queued.
@MainActor
final class SculptorAppDelegate: NSObject, NSApplicationDelegate {
    /// Set once the SwiftUI model exists. Files that arrive before then are
    /// held so a launch-time open is not dropped.
    var model: SculptorAppModel? {
        didSet {
            guard let pending = pendingURL else { return }
            pendingURL = nil
            _ = model?.accept(pending)
        }
    }

    private var pendingURL: URL?

    /// The modern entry point, and the one SwiftUI's delegate adaptor actually
    /// forwards. `openFiles` below is kept for callers that still use it.
    nonisolated func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        Task { @MainActor in self.open(first) }
    }

    nonisolated func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else { return }
        let url = URL(fileURLWithPath: first)
        // Delivered on the main thread, but not statically isolated, so the hop
        // makes that explicit rather than assumed.
        Task { @MainActor in
            let opened = self.open(url)
            sender.reply(toOpenOrPrint: opened ? .success : .failure)
        }
    }

    @discardableResult
    private func open(_ url: URL) -> Bool {
        guard let model else {
            // Arrived before the window exists; replay it once the model lands.
            pendingURL = url
            return true
        }
        return model.accept(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ImageKidSculptorApp: App {
    @NSApplicationDelegateAdaptor(SculptorAppDelegate.self) private var delegate
    @StateObject private var model = SculptorAppModel()

    var body: some Scene {
        WindowGroup {
            SculptorView(model: model)
                .task {
                    delegate.model = model
                    await model.warmUp()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Image…") { model.chooseImage() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Button("Export 3D Model…") { model.exportModel() }
                    .keyboardShortcut("e")
                    .disabled(!model.canExport)
            }
        }

        Settings {
            SculptorSettingsView(model: model)
        }
    }
}
