import SwiftUI
import UIKit

/// How the canvas behind the working image is drawn. Mirrors the macOS app.
enum CanvasBackground: String, CaseIterable, Identifiable {
    case light
    case dark
    case checkerboard
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .checkerboard: "Checkerboard"
        case .custom: "Custom"
        }
    }
}

/// Persisted display settings for the editor canvas.
@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("canvasBackground") var canvasBackgroundRaw = CanvasBackground.checkerboard.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("customCanvasColor") var customCanvasColorHex = "#7ABBDC" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("imageCornerRadius") var imageCornerRadius = 10.0 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("showCanvasBorder") var showCanvasBorder = true {
        willSet { objectWillChange.send() }
    }

    var canvasBackground: CanvasBackground {
        get { CanvasBackground(rawValue: canvasBackgroundRaw) ?? .checkerboard }
        set { canvasBackgroundRaw = newValue.rawValue }
    }

    var customCanvasColor: Color {
        get { Color(hex: customCanvasColorHex) ?? Color(red: 0.48, green: 0.73, blue: 0.86) }
        set { customCanvasColorHex = newValue.hexString }
    }

    /// Solid canvas colour for the non-checkerboard modes.
    var canvasColor: Color {
        switch canvasBackground {
        case .light: Color(red: 0.94, green: 0.94, blue: 0.92)
        case .dark: Color(red: 0.08, green: 0.085, blue: 0.095)
        case .checkerboard: Color(.secondarySystemBackground)
        case .custom: customCanvasColor
        }
    }

    /// A border colour that stays legible against the current canvas.
    var canvasBorderColor: Color {
        switch canvasBackground {
        case .dark: .white.opacity(0.34)
        case .light: .black.opacity(0.24)
        case .checkerboard: .primary.opacity(0.32)
        case .custom: customCanvasColor.isDark ? .white.opacity(0.4) : .black.opacity(0.3)
        }
    }
}

extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let integer = Int(value, radix: 16) else { return nil }
        self.init(
            red: Double((integer >> 16) & 0xff) / 255,
            green: Double((integer >> 8) & 0xff) / 255,
            blue: Double(integer & 0xff) / 255
        )
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) < 0.5
    }
}
