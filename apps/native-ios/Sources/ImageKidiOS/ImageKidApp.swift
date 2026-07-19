import SwiftUI

@main
struct ImageKidApp: App {
    @StateObject private var model = InferenceModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onOpenURL { url in
                    model.openExternalImage(at: url)
                }
        }
    }
}
