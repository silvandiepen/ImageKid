import AppKit
import FekthorKit
import SwiftUI

/// The editor canvas surround's look: a colour + opacity wash over the
/// window's black-glass backdrop, so the canvas reads like the header and
/// footer chrome instead of an opaque slab. App-global (it's window
/// chrome, not a workspace standard), persisted through `AppDefaults`,
/// edited in Fekthor ▸ Settings… (⌘,).
@MainActor
final class CanvasAppearance: ObservableObject {
    static let shared = CanvasAppearance()

    static let defaultOpacity: Double = 0

    /// Canvas background colour as "#rrggbb"; nil = black. With the
    /// default 0 opacity the surround is pure backdrop glass — the wash
    /// only appears once the opacity comes up.
    @Published var backgroundHex: String? {
        didSet { AppDefaults.store.set(backgroundHex, forKey: Self.hexKey) }
    }

    /// 0 = pure backdrop glass, 1 = fully opaque.
    @Published var backgroundOpacity: Double {
        didSet { AppDefaults.store.set(backgroundOpacity, forKey: Self.opacityKey) }
    }

    private static let hexKey = "fekthor.canvas.backgroundHex"
    private static let opacityKey = "fekthor.canvas.backgroundOpacity"

    private init() {
        backgroundHex = AppDefaults.store.string(forKey: Self.hexKey)
        backgroundOpacity =
            AppDefaults.store.object(forKey: Self.opacityKey) as? Double
            ?? Self.defaultOpacity
    }

    /// The base colour before the opacity wash.
    var baseColor: Color {
        guard let backgroundHex, let c = PaintValue.parseHex(backgroundHex) else {
            return .black
        }
        return Color(
            red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    /// What the canvas actually paints behind the artboard.
    var effectiveBackground: Color {
        baseColor.opacity(max(0, min(1, backgroundOpacity)))
    }

    func reset() {
        backgroundHex = nil
        backgroundOpacity = Self.defaultOpacity
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
                ColorPicker("Colour", selection: colorBinding, supportsOpacity: false)
                LabeledContent("Opacity") {
                    HStack(spacing: 8) {
                        Slider(value: $appearance.backgroundOpacity, in: 0...1)
                        Text(String(format: "%.0f%%", appearance.backgroundOpacity * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
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

    private var colorBinding: Binding<Color> {
        Binding(
            get: { appearance.baseColor },
            set: { picked in
                let ns = NSColor(picked).usingColorSpace(.sRGB) ?? .black
                appearance.backgroundHex = String(
                    format: "#%02x%02x%02x",
                    Int(round(ns.redComponent * 255)),
                    Int(round(ns.greenComponent * 255)),
                    Int(round(ns.blueComponent * 255)))
            })
    }
}
