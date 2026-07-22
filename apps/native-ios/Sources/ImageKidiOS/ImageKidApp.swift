import SwiftUI

@main
struct ImageKidApp: App {
    @StateObject private var model = InferenceModel()
    @StateObject private var settings = AppSettings()
    @StateObject private var fonts = GoogleFontsManager()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .environmentObject(settings)
                .environmentObject(fonts)
                .onOpenURL { url in
                    model.openExternalImage(at: url)
                }
        }
    }
}
