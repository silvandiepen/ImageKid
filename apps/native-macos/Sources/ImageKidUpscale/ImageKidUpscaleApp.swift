import AppKit
import SwiftUI

@main
struct ImageKidUpscaleApp: App {
    @StateObject private var model = CompanionBatchModel()

    var body: some Scene {
        WindowGroup {
            ImageKidUpscaleView(model: model)
        }
        .defaultSize(width: 1_120, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Images...") {
                    model.openFiles()
                }
                .keyboardShortcut("o")
            }
            CommandGroup(after: .help) {
                Button("ImageKid Upscale Support") {
                    NSWorkspace.shared.open(URL(string: "https://imagekid.hakobs.com/support")!)
                }
                Button("Privacy Policy") {
                    NSWorkspace.shared.open(URL(string: "https://imagekid.hakobs.com/privacy")!)
                }
            }
        }
    }
}
