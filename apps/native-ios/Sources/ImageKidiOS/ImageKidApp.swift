import SwiftUI

@main
struct ImageKidApp: App {
    @StateObject private var model = InferenceModel()
    @StateObject private var settings = AppSettings()

    init() {
        // UI-test launches start from a clean slate (see UITestSupport).
        UITestSupport.prepareFreshState()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .environmentObject(settings)
                .onOpenURL { url in
                    model.openExternalImage(at: url)
                }
                .onAppear {
                    UITestSupport.accelerateAnimations()
                    if UITestSupport.wantsDemoImage, model.items.isEmpty {
                        model.setSource(UITestSupport.makeDemoImage())
                    } else if UITestSupport.wantsSampleImage, model.items.isEmpty {
                        model.setSource(UITestSupport.makeSampleImage())
                    }
                }
        }
    }
}
