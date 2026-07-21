import SwiftUI

@main
struct ImageKidCutoutApp: App {
    @StateObject private var model = CompanionBatchModel()

    var body: some Scene {
        WindowGroup {
            ImageKidCutoutView(model: model)
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
