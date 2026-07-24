import AppKit
import ImageKidKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// The canvas background model is shared with Fekthor — see
// `ImageKidKit.CanvasBackground`.

enum BackgroundRemovalEngine: String, CaseIterable, Identifiable {
    case builtIn
    case bestQuality

    var id: String { rawValue }

    var label: String {
        switch self {
        case .builtIn: "Built-in"
        case .bestQuality: "Best Quality"
        }
    }
}

enum UpscaleEngine: String, CaseIterable, Identifiable {
    case standard
    case bestQuality

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .bestQuality: "Best Quality"
        }
    }
}

enum UpscaleContentMode: String, CaseIterable, Identifiable {
    case automatic
    case textAndUI
    case photoArtwork

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Auto"
        case .textAndUI: "Text & UI"
        case .photoArtwork: "Photo & Artwork"
        }
    }
}

/// Quality grade for Magic ▸ Enhance Image. We surface grades, not model names:
/// Quick is the built-in Core Image sharpen (instant, no download); High and Max
/// are on-device AI models downloaded on demand.
enum EnhanceQuality: String, CaseIterable, Identifiable {
    case quick
    case high
    case max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: "Quick"
        case .high: "High"
        case .max: "Max"
        }
    }

    var detail: String {
        switch self {
        case .quick: "Instant. Built-in, no download."
        case .high: "Sharper AI detail."
        case .max: "Richest, most realistic detail."
        }
    }

    /// The model this grade needs downloaded (nil = built-in Core Image).
    var requiredModel: CoreMLModel? {
        switch self {
        case .quick: nil
        case .high: .realESRGAN
        case .max: .auraSR
        }
    }
}

/// Output size for Enhance. AI models always upscale 4×; we fit the result to the
/// requested multiple of the source.
enum EnhanceSize: String, CaseIterable, Identifiable {
    case same
    case x2
    case x4

    var id: String { rawValue }

    var label: String {
        switch self {
        case .same: "Same"
        case .x2: "2×"
        case .x4: "4×"
        }
    }

    var factor: CGFloat {
        switch self {
        case .same: 1
        case .x2: 2
        case .x4: 4
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("appearanceMode") var appearanceModeRaw = AppearanceMode.system.rawValue {
        willSet { objectWillChange.send() }
    }

    // The canvas background: a style, the Custom-style colour, and the
    // opacity wash — the three fields of the shared `CanvasBackground`,
    // stored separately so existing installs keep their style/colour.
    @AppStorage("canvasBackground") var canvasBackgroundRaw = CanvasBackground.imageKidDefault.style.rawValue {
        willSet { objectWillChange.send() }
    }

    @AppStorage("customCanvasBackground") var customCanvasBackgroundRaw = CanvasBackground.defaultCustomHex {
        willSet { objectWillChange.send() }
    }

    @AppStorage("canvasBackgroundOpacity") var canvasBackgroundOpacity = 1.0 {
        willSet { objectWillChange.send() }
    }

    @AppStorage("imageCornerRadius") var imageCornerRadius = 8.0 {
        willSet { objectWillChange.send() }
    }

    @AppStorage("backgroundRemovalEngine") var backgroundRemovalEngineRaw = BackgroundRemovalEngine.builtIn.rawValue {
        willSet { objectWillChange.send() }
    }

    @AppStorage("upscaleEngine") var upscaleEngineRaw = UpscaleEngine.standard.rawValue {
        willSet { objectWillChange.send() }
    }

    @AppStorage("upscaleContentMode") var upscaleContentModeRaw = UpscaleContentMode.automatic.rawValue {
        willSet { objectWillChange.send() }
    }

    @AppStorage("showInFinderContextMenus") var showInFinderContextMenus = true {
        willSet { objectWillChange.send() }
    }

    @AppStorage("quickActionsJSON") var quickActionsJSON = "" {
        willSet { objectWillChange.send() }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue }
    }

    /// The shared canvas-background model, assembled from the three stored
    /// fields. Setting it (or mutating a sub-field) writes them back.
    var canvasBackground: CanvasBackground {
        get {
            CanvasBackground(
                style: CanvasBackground.Style(rawValue: canvasBackgroundRaw) ?? .checkerboard,
                customHex: customCanvasBackgroundRaw,
                opacity: canvasBackgroundOpacity)
        }
        set {
            canvasBackgroundRaw = newValue.style.rawValue
            customCanvasBackgroundRaw = newValue.customHex
            canvasBackgroundOpacity = newValue.opacity
        }
    }

    var backgroundRemovalEngine: BackgroundRemovalEngine {
        get { BackgroundRemovalEngine(rawValue: backgroundRemovalEngineRaw) ?? .builtIn }
        set { backgroundRemovalEngineRaw = newValue.rawValue }
    }

    var upscaleEngine: UpscaleEngine {
        get { UpscaleEngine(rawValue: upscaleEngineRaw) ?? .standard }
        set { upscaleEngineRaw = newValue.rawValue }
    }

    var upscaleContentMode: UpscaleContentMode {
        get { UpscaleContentMode(rawValue: upscaleContentModeRaw) ?? .automatic }
        set { upscaleContentModeRaw = newValue.rawValue }
    }

    var quickActions: [QuickActionDefinition] {
        get {
            guard let data = quickActionsJSON.data(using: .utf8),
                  let definitions = try? JSONDecoder().decode([QuickActionDefinition].self, from: data),
                  !definitions.isEmpty else {
                return QuickActionDefaults.definitions
            }
            return mergedQuickActions(definitions)
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            quickActionsJSON = json
        }
    }

    private func mergedQuickActions(_ stored: [QuickActionDefinition]) -> [QuickActionDefinition] {
        var result = stored
        let storedIDs = Set(stored.map(\.id))
        let missingDefaults = QuickActionDefaults.definitions.filter { !storedIDs.contains($0.id) }
        result.insert(contentsOf: missingDefaults, at: 0)
        return result
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        let value = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let integer = Int(value, radix: 16) else { return nil }
        self.init(
            red: CGFloat((integer >> 16) & 0xff) / 255,
            green: CGFloat((integer >> 8) & 0xff) / 255,
            blue: CGFloat(integer & 0xff) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}
