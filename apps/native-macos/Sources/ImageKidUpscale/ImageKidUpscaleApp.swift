import SwiftUI

@main
struct ImageKidUpscaleApp: App {
    @StateObject private var model = CompanionBatchModel()

    var body: some Scene {
        WindowGroup {
            ImageKidUpscaleView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Images...") {
                    model.openFiles()
                }
                .keyboardShortcut("o")
            }
        }
    }
}
