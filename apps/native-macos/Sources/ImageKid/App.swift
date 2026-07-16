import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var media: MediaItem?
    @Published var activeTool: Tool = .view
    @Published var errorMessage: String?
    @Published var isShowingResize = false
    @Published var isShowingExport = false

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    func load(_ url: URL) {
        do {
            media = try MediaLoader.load(url: url)
            activeTool = .view
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func paste() {
        if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first {
            load(url)
            return
        }

        if let image = NSImage(pasteboard: .general) {
            media = .image(ImageSession(sourceURL: nil, sourceImage: image))
            activeTool = .view
            return
        }

        errorMessage = "The clipboard does not contain a supported image or video file."
    }

    func resetView() {
        switch media {
        case .image(let session): session.resetView()
        case .video(let session):
            session.zoom = 1
            session.pan = .zero
        case nil: break
        }
    }

    func cancelCurrentTool() {
        if case .image(let session) = media {
            if activeTool == .crop {
                session.cancelCrop()
            }
            session.liveSampleColor = nil
            session.liveSampleLocation = nil
        }
        activeTool = .view
    }

    func requestExport() {
        guard case .image = media else {
            errorMessage = "Video export is not implemented in the current foundation build."
            return
        }
        isShowingExport = true
    }

    func exportImage(options: ImageExportOptions) {
        guard case .image(let session) = media else {
            errorMessage = "Video export is not implemented in the current foundation build."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.contentType]
        panel.nameFieldStringValue = suggestedExportName(for: session, format: options.format)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ImageRenderer.write(session, to: url, options: options)
            session.isDirty = false
            if options.revealAfterExport {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func suggestedExportName(for session: ImageSession, format: ImageExportFormat) -> String {
        let sourceName = session.sourceURL?.deletingPathExtension().lastPathComponent ?? "ImageKid Export"
        return sourceName + "-edited." + format.fileExtension
    }
}

struct AppCommands: Commands {
    @FocusedObject private var appModel: AppModel?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { appModel?.openPanel() }
                .keyboardShortcut("o")
                .disabled(appModel == nil)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                _ = NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x")
            .disabled(appModel == nil)

            Button("Copy") {
                _ = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("c")
            .disabled(appModel == nil)

            Button("Paste") {
                let handledByResponder = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                if !handledByResponder {
                    appModel?.paste()
                }
            }
            .keyboardShortcut("v")
            .disabled(appModel == nil)
        }

        CommandMenu("Tools") {
            Button("View") { appModel?.activeTool = .view }
                .keyboardShortcut("v", modifiers: [])
                .disabled(appModel == nil)
            Button("Pick Colour") { appModel?.activeTool = .pickColor }
                .keyboardShortcut("p", modifiers: [])
                .disabled(appModel == nil)
            Button("Crop") { appModel?.activeTool = .crop }
                .keyboardShortcut("c", modifiers: [])
                .disabled(appModel == nil)
            Divider()
            Button("Draw") { appModel?.activeTool = .draw }
                .keyboardShortcut("d", modifiers: [])
                .disabled(appModel == nil)
            Button("Text") { appModel?.activeTool = .text }
                .keyboardShortcut("t", modifiers: [])
                .disabled(appModel == nil)
            Divider()
            Button("Resize…") { appModel?.isShowingResize = true }
                .keyboardShortcut("r", modifiers: [])
                .disabled(appModel == nil)
            Button("Cancel Current Tool") { appModel?.cancelCurrentTool() }
                .keyboardShortcut(.cancelAction)
                .disabled(appModel == nil)
        }

        CommandMenu("View") {
            Button("Fit to Window") { appModel?.resetView() }
                .keyboardShortcut("0", modifiers: [])
                .disabled(appModel == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Export…") { appModel?.requestExport() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(appModel == nil)
        }
    }
}

final class ImageKidApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = ImageKidIconRenderer.makeNSImage() {
            NSApplication.shared.applicationIconImage = icon
        }
    }
}

struct AppWindowRoot: View {
    @StateObject private var appModel = AppModel()

    var body: some View {
        ContentView()
            .environmentObject(appModel)
            .focusedSceneObject(appModel)
            .frame(minWidth: 720, minHeight: 480)
    }
}

@main
struct ImageKidApp: App {
    @NSApplicationDelegateAdaptor(ImageKidApplicationDelegate.self) private var applicationDelegate

    var body: some Scene {
        WindowGroup {
            AppWindowRoot()
        }
        .defaultSize(width: 940, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands()
        }
    }
}
