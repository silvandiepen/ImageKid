import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var media: MediaItem?
    @Published var activeTool: Tool = .view
    @Published var errorMessage: String?
    @Published var isShowingResize = false

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

    func exportImage() {
        guard case .image(let session) = media else {
            errorMessage = "Video export is not implemented in the current foundation build."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = suggestedExportName(for: session)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let type = UTType(filenameExtension: url.pathExtension) ?? .png

        do {
            try ImageRenderer.write(session, to: url, type: type)
            session.isDirty = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func suggestedExportName(for session: ImageSession) -> String {
        let sourceName = session.sourceURL?.deletingPathExtension().lastPathComponent ?? "ImageKid Export"
        return sourceName + "-edited.png"
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
            Button("Rectangle Annotation") { appModel.activeTool = .rectangle }
            Button("Text Annotation") { appModel.activeTool = .text }
            Divider()
            Button("Resize…") { appModel.isShowingResize = true }
                .keyboardShortcut("r", modifiers: [])
        }

        CommandMenu("View") {
            Button("Fit to Window") { appModel.resetView() }
                .keyboardShortcut("0", modifiers: [])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Export…") { appModel.exportImage() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}

@main
struct ImageKidApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands(appModel: appModel)
        }
    }
}
