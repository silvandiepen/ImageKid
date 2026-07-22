import SwiftUI

extension Notification.Name {
    static let fekthorNewFile = Notification.Name("fekthor.newFile")
    static let fekthorOpen = Notification.Name("fekthor.open")
    static let fekthorSave = Notification.Name("fekthor.save")
    static let fekthorSaveAs = Notification.Name("fekthor.saveAs")
    static let fekthorTraceImage = Notification.Name("fekthor.traceImage")
}

@main
struct FekthorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 940, minHeight: 620)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") {
                    NotificationCenter.default.post(name: .fekthorNewFile, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Open…") {
                    NotificationCenter.default.post(name: .fekthorOpen, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .fekthorSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") {
                    NotificationCenter.default.post(name: .fekthorSaveAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Trace Image…") {
                    NotificationCenter.default.post(name: .fekthorTraceImage, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}
