import AppKit
import ImageKidKit
import SwiftUI

/// Lets a menu command reach the queue of whichever window is in front. Each window
/// owns its own model, so there is no single instance for the command to talk to.
struct BatchModelKey: FocusedValueKey {
    typealias Value = CompanionBatchModel
}

extension FocusedValues {
    var batchModel: CompanionBatchModel? {
        get { self[BatchModelKey.self] }
        set { self[BatchModelKey.self] = newValue }
    }
}

@main
struct ImageKidCutoutApp: App {
    var body: some Scene {
        WindowGroup(id: Self.windowID) {
            // Created here rather than on the App, so Command-N gives a window with a
            // queue of its own instead of a second view onto the same one.
            ImageKidCutoutWindow()
        }
        .defaultSize(width: 1_120, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CutoutCommands(windowID: Self.windowID)
        }
    }

    static let windowID = "cutout"
}

private struct ImageKidCutoutWindow: View {
    @StateObject private var model = CompanionBatchModel()

    var body: some View {
        ImageKidCutoutView(model: model)
            .focusedSceneValue(\.batchModel, model)
    }
}

private struct CutoutCommands: Commands {
    let windowID: String

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.batchModel) private var model

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Cutout") {
                AboutWindow.show(ImageKidSuiteAbout.info(for: .cutout))
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(id: windowID)
            }
            .keyboardShortcut("n")

            Button("Open Images...") {
                model?.openFiles()
            }
            .keyboardShortcut("o")
            .disabled(model == nil)
        }
        CommandGroup(after: .help) {
            Button("Cutout Support") {
                NSWorkspace.shared.open(URL(string: "https://imagekid.hakobs.com/support")!)
            }
            Button("Privacy Policy") {
                NSWorkspace.shared.open(URL(string: "https://imagekid.hakobs.com/privacy")!)
            }
        }
    }
}
