import SwiftUI

/// The canvas background, shared by ImageKid and Fekthor so both offer the
/// same options and paint them identically: a solid tone (Light / Dark /
/// Custom colour) OR a transparency checkerboard, washed at an opacity that
/// lets whatever sits behind the canvas — ImageKid's window, Fekthor's black
/// glass — show through.
///
/// A plain value type: each app owns where it is stored (both persist a
/// style, a hex and an opacity) and renders it with `CanvasBackgroundView`.
public struct CanvasBackground: Equatable, Sendable {
    public enum Style: String, CaseIterable, Identifiable, Sendable {
        case light
        case dark
        case checkerboard
        case custom

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            case .checkerboard: "Transparent"
            case .custom: "Custom"
            }
        }

        /// The checkerboard is the transparency indicator; it draws its own
        /// pattern rather than a flat colour.
        public var isCheckerboard: Bool { self == .checkerboard }
    }

    public var style: Style
    /// The colour used when `style == .custom`, as `#rrggbb`.
    public var customHex: String
    /// The wash over whatever is behind the canvas (0 = fully see-through,
    /// 1 = opaque).
    public var opacity: Double

    public init(style: Style, customHex: String = CanvasBackground.defaultCustomHex, opacity: Double = 1) {
        self.style = style
        self.customHex = customHex
        self.opacity = opacity.clampedUnit
    }

    public static let defaultCustomHex = "#7ABBDC"

    /// The two apps' historical defaults, kept: ImageKid shows the
    /// transparency checkerboard, Fekthor shows pure glass (a black wash at
    /// zero opacity — the colour is irrelevant until the opacity comes up).
    public static let imageKidDefault = CanvasBackground(style: .checkerboard, opacity: 1)
    public static let fekthorDefault = CanvasBackground(style: .custom, customHex: "#000000", opacity: 0)

    /// The flat base colour for the solid styles; nil for the checkerboard,
    /// which paints itself. Opacity is NOT applied here — the renderer washes
    /// the whole layer so the checkerboard fades with it too.
    public var baseColor: Color? {
        switch style {
        case .light: Color(red: 0.94, green: 0.94, blue: 0.92)
        case .dark: Color(red: 0.08, green: 0.085, blue: 0.095)
        case .checkerboard: nil
        case .custom: CanvasBackground.color(fromHex: customHex) ?? Color(red: 0.47, green: 0.73, blue: 0.86)
        }
    }

    /// Whether the effective background reads as dark — for choosing a canvas
    /// border/handle colour that stays visible against it. The checkerboard
    /// reads light; a low-opacity wash defers to the (dark) surface behind.
    public var readsAsDark: Bool {
        switch style {
        case .checkerboard: return false
        case .light: return false
        case .dark: return opacity > 0.5
        case .custom:
            guard let rgb = CanvasBackground.rgb(fromHex: customHex) else { return false }
            let luminance = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
            // A translucent light colour still lets the dark surface win.
            return luminance < 0.45 || opacity <= 0.5
        }
    }

    // MARK: - Hex helpers

    public static func rgb(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = Int(s, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xff) / 255,
            Double((value >> 8) & 0xff) / 255,
            Double(value & 0xff) / 255)
    }

    public static func color(fromHex hex: String) -> Color? {
        guard let rgb = rgb(fromHex: hex) else { return nil }
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    public static func hex(from color: Color) -> String {
        #if canImport(AppKit)
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(
            format: "#%02x%02x%02x",
            Int((ns.redComponent * 255).rounded()),
            Int((ns.greenComponent * 255).rounded()),
            Int((ns.blueComponent * 255).rounded()))
        #else
        return "#000000"
        #endif
    }
}

extension Double {
    fileprivate var clampedUnit: Double { Swift.max(0, Swift.min(1, self)) }
}

// MARK: - Rendering

/// The transparency checkerboard. Light in a light appearance, quiet greys in
/// a dark one, so a transparent canvas reads the same everywhere both apps run.
public struct CheckerboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    public var cellSize: CGFloat

    public init(cellSize: CGFloat = 12) {
        self.cellSize = cellSize
    }

    public var body: some View {
        let light = colorScheme == .dark ? Color.white.opacity(0.11) : Color.white
        let dark = colorScheme == .dark ? Color.white.opacity(0.055) : Color.gray.opacity(0.18)
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            let rows = Int(size.height / cellSize)
            let cols = Int(size.width / cellSize)
            guard rows >= 0, cols >= 0 else { return }
            for row in 0...rows {
                for column in 0...cols where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * cellSize, y: CGFloat(row) * cellSize,
                                width: cellSize, height: cellSize)),
                        with: .color(dark))
                }
            }
        }
    }
}

/// Paints a `CanvasBackground`: the checkerboard, or the base colour — both
/// washed at the background's opacity so a low opacity reveals the surface
/// behind (ImageKid's window, Fekthor's glass).
public struct CanvasBackgroundView: View {
    public let background: CanvasBackground
    public var checkerCell: CGFloat

    public init(background: CanvasBackground, checkerCell: CGFloat = 18) {
        self.background = background
        self.checkerCell = checkerCell
    }

    public var body: some View {
        Group {
            if background.style.isCheckerboard {
                CheckerboardBackground(cellSize: checkerCell)
            } else {
                (background.baseColor ?? .black)
            }
        }
        .opacity(background.opacity)
    }
}

// MARK: - Shared editor

/// The canvas-background control both apps' Settings embed: a style picker,
/// a colour well for the Custom style, and the opacity wash slider — so the
/// options are literally the same view in both apps.
public struct CanvasBackgroundControls: View {
    @Binding public var background: CanvasBackground
    /// Hidden where it makes no sense (an always-opaque host). ImageKid and
    /// Fekthor both show it — the wash is the shared "transparency" control.
    public var showsOpacity: Bool

    public init(background: Binding<CanvasBackground>, showsOpacity: Bool = true) {
        self._background = background
        self.showsOpacity = showsOpacity
    }

    public var body: some View {
        Picker("Background", selection: styleBinding) {
            ForEach(CanvasBackground.Style.allCases) { style in
                Text(style.label).tag(style)
            }
        }
        .pickerStyle(.segmented)

        if background.style == .custom {
            ColorPicker("Colour", selection: colorBinding, supportsOpacity: false)
        }

        if showsOpacity {
            LabeledContent("Opacity") {
                HStack(spacing: 8) {
                    Slider(value: opacityBinding, in: 0...1)
                    Text(String(format: "%.0f%%", background.opacity * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }

        CanvasBackgroundView(background: background)
            .frame(height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.secondary.opacity(0.35)))
    }

    private var styleBinding: Binding<CanvasBackground.Style> {
        Binding(get: { background.style }, set: { background.style = $0 })
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { background.opacity }, set: { background.opacity = max(0, min(1, $0)) })
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { CanvasBackground.color(fromHex: background.customHex) ?? .blue },
            set: { background.customHex = CanvasBackground.hex(from: $0) })
    }
}
