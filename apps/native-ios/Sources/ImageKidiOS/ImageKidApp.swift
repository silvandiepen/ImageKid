import SwiftUI

@main
struct ImageKidApp: App {
    @StateObject private var model = InferenceModel()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .environmentObject(settings)
                .onOpenURL { url in
                    model.openExternalImage(at: url)
                }
        }
    }
}
