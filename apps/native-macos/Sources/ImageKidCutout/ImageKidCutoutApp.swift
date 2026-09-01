import AppKit
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
            CommandGroup(after: .help) {
                Button("ImageKid Cutout Support") {
                    NSWorkspace.shared.open(URL(string: "https://imagekid.hakobs.com/support")!)
                }
                Button("Privacy Policy") {
                    NSWorkspace.shared.open(URL(string: "https://imagekid.hakobs.com/privacy")!)
                }
            }
        }
    }
}
