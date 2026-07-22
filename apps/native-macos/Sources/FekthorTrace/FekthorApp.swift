import SwiftUI

extension Notification.Name {
    static let fekthorNewFile = Notification.Name("fekthor.newFile")
    static let fekthorOpen = Notification.Name("fekthor.open")
    static let fekthorOpenWorkspace = Notification.Name("fekthor.openWorkspace")
    static let fekthorSave = Notification.Name("fekthor.save")
    static let fekthorSaveAs = Notification.Name("fekthor.saveAs")
    static let fekthorTraceImage = Notification.Name("fekthor.traceImage")
    static let fekthorGroup = Notification.Name("fekthor.group")
    static let fekthorUngroup = Notification.Name("fekthor.ungroup")
    static let fekthorBringForward = Notification.Name("fekthor.bringForward")
    static let fekthorSendBackward = Notification.Name("fekthor.sendBackward")
    static let fekthorBringToFront = Notification.Name("fekthor.bringToFront")
    static let fekthorSendToBack = Notification.Name("fekthor.sendToBack")
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
                Button("Open Workspace…") {
                    NotificationCenter.default.post(name: .fekthorOpenWorkspace, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
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
            CommandMenu("Object") {
                Button("Group") {
                    NotificationCenter.default.post(name: .fekthorGroup, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)
                Button("Ungroup") {
                    NotificationCenter.default.post(name: .fekthorUngroup, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button("Bring to Front") {
                    NotificationCenter.default.post(name: .fekthorBringToFront, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .option])
                Button("Bring Forward") {
                    NotificationCenter.default.post(name: .fekthorBringForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
                Button("Send Backward") {
                    NotificationCenter.default.post(name: .fekthorSendBackward, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)
                Button("Send to Back") {
                    NotificationCenter.default.post(name: .fekthorSendToBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .option])
            }
        }
    }
}
