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
    @ObservedObject var appModel: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { appModel.openPanel() }
                .keyboardShortcut("o")
        }

        CommandGroup(after: .pasteboard) {
            Button("Paste Media") { appModel.paste() }
                .keyboardShortcut("v")
        }

        CommandMenu("Tools") {
            Button("View") { appModel.activeTool = .view }
                .keyboardShortcut("v", modifiers: [])
            Button("Pick Colour") { appModel.activeTool = .pickColor }
                .keyboardShortcut("p", modifiers: [])
            Button("Crop") { appModel.activeTool = .crop }
                .keyboardShortcut("c", modifiers: [])
            Divider()
            Button("Draw") { appModel.activeTool = .draw }
                .keyboardShortcut("d", modifiers: [])
            Button("Text") { appModel.activeTool = .text }
                .keyboardShortcut("t", modifiers: [])
            Divider()
            Button("Resize…") { appModel.isShowingResize = true }
                .keyboardShortcut("r", modifiers: [])
            Button("Cancel Current Tool") { appModel.cancelCurrentTool() }
                .keyboardShortcut(.cancelAction)
        }

        CommandMenu("View") {
            Button("Fit to Window") { appModel.resetView() }
                .keyboardShortcut("0", modifiers: [])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Export…") { appModel.requestExport() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
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

@main
struct ImageKidApp: App {
    @NSApplicationDelegateAdaptor(ImageKidApplicationDelegate.self) private var applicationDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 940, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands(appModel: appModel)
        }
    }
}
