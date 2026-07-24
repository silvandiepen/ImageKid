import AppKit
import ImageKidKit
import SwiftUI

/// The editor canvas surround's look: the shared `CanvasBackground` (colour
/// presets, a custom colour, or the transparency checkerboard, washed at an
/// opacity that lets the window's black glass show through) — the SAME model
/// and controls ImageKid uses. App-global (it's window chrome, not a
/// workspace standard), persisted through `AppDefaults`, edited in
/// Fekthor ▸ Settings… (⌘,).
@MainActor
final class CanvasAppearance: ObservableObject {
    static let shared = CanvasAppearance()

    /// Fekthor's default surround is pure glass — a wash at zero opacity.
    @Published var background: CanvasBackground {
        didSet { persist() }
    }

    private static let styleKey = "fekthor.canvas.backgroundStyle"
    private static let hexKey = "fekthor.canvas.backgroundHex"
    private static let opacityKey = "fekthor.canvas.backgroundOpacity"

    private init() {
        let style =
            (AppDefaults.store.string(forKey: Self.styleKey))
            .flatMap(CanvasBackground.Style.init(rawValue:))
            // Pre-shared installs stored only a hex: a custom colour then.
            ?? (AppDefaults.store.string(forKey: Self.hexKey) != nil ? .custom : nil)
            ?? CanvasBackground.fekthorDefault.style
        let hex = AppDefaults.store.string(forKey: Self.hexKey)
            ?? CanvasBackground.fekthorDefault.customHex
        let opacity =
            AppDefaults.store.object(forKey: Self.opacityKey) as? Double
            ?? CanvasBackground.fekthorDefault.opacity
        background = CanvasBackground(style: style, customHex: hex, opacity: opacity)
    }

    private func persist() {
        AppDefaults.store.set(background.style.rawValue, forKey: Self.styleKey)
        AppDefaults.store.set(background.customHex, forKey: Self.hexKey)
        AppDefaults.store.set(background.opacity, forKey: Self.opacityKey)
    }

    func reset() {
        background = CanvasBackground.fekthorDefault
    }
}

/// Fekthor ▸ Settings… (⌘,): app-wide appearance preferences. Workspace
/// standards (grid, drawing defaults) stay in Workspace Settings — this is
/// only what belongs to the app window itself.
struct FekthorSettingsView: View {
    @ObservedObject private var appearance = CanvasAppearance.shared

    var body: some View {
        Form {
            Section("Canvas background") {
                // The shared control — identical to ImageKid's Settings.
                CanvasBackgroundControls(background: $appearance.background)
                Button("Reset to Default") { appearance.reset() }
                Text("Lower opacity lets the window's glass show through the canvas, like the header and footer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}
