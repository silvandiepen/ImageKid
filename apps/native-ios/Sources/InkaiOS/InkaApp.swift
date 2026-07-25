import SwiftUI

/// Inka for iPad — the family's drawing & illustration app. P1 walking skeleton:
/// boots to the shared HomeScreen, opens a Metal canvas, paints with the shared
/// BrushKit/BrushRender engine (Apple Pencil pressure/tilt), exports a PNG.
@main
struct InkaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.accentColor)
                .preferredColorScheme(.dark)
        }
    }
}
