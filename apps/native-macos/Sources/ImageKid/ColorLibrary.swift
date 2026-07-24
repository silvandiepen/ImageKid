import AppKit
import ImageKidKit
import SwiftUI
import ImageKidCore

struct SwatchColor: Identifiable, Codable, Hashable {
    var id: UUID
    var hex: String

    init(id: UUID = UUID(), hex: String) {
        self.id = id
        self.hex = hex
    }

    init(id: UUID = UUID(), color: NSColor) {
        self.id = id
        self.hex = ColorHex.string(from: color)
    }

    var nsColor: NSColor { ColorHex.color(from: hex) ?? .white }
    var color: Color { Color(nsColor: nsColor) }
}

struct SwatchSet: Identifiable, Codable {
    var id: UUID
    var name: String
    var colors: [SwatchColor]
    /// The base set drives default colours offered to shapes, lines, and text.
    var isBase: Bool

    init(id: UUID = UUID(), name: String, colors: [SwatchColor], isBase: Bool = false) {
        self.id = id
        self.name = name
        self.colors = colors
        self.isBase = isBase
    }
}

/// App-wide colour swatch library, persisted to UserDefaults.
@MainActor
final class ColorLibrary: ObservableObject {
    @Published var sets: [SwatchSet] { didSet { save() } }

    /// App-wide foreground/background colours (Photoshop-style), used as the
    /// default stroke/text (foreground) and fill (background) colours.
    @Published var foregroundHex: String { didSet { UserDefaults.standard.set(foregroundHex, forKey: "colorLibrary.foreground") } }
    @Published var backgroundHex: String { didSet { UserDefaults.standard.set(backgroundHex, forKey: "colorLibrary.background") } }

    private let storeKey = "colorLibrary.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let decoded = try? JSONDecoder().decode([SwatchSet].self, from: data),
           !decoded.isEmpty {
            sets = decoded
        } else {
            sets = [ColorLibrary.defaultBaseSet()]
        }
        foregroundHex = UserDefaults.standard.string(forKey: "colorLibrary.foreground") ?? "#111111"
        backgroundHex = UserDefaults.standard.string(forKey: "colorLibrary.background") ?? "#FFFFFF"
    }

    var foreground: NSColor {
        get { ColorHex.color(from: foregroundHex) ?? .black }
        set { foregroundHex = ColorHex.string(from: newValue) }
    }

    var background: NSColor {
        get { ColorHex.color(from: backgroundHex) ?? .white }
        set { backgroundHex = ColorHex.string(from: newValue) }
    }

    func swapForegroundBackground() {
        let f = foregroundHex
        foregroundHex = backgroundHex
        backgroundHex = f
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sets) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    var baseSet: SwatchSet? { sets.first(where: { $0.isBase }) ?? sets.first }

    /// Colours the drawing/text tools offer as quick picks.
    var baseColors: [SwatchColor] { baseSet?.colors ?? [] }

    func addColor(_ color: NSColor, to setID: UUID) {
        guard let index = sets.firstIndex(where: { $0.id == setID }) else { return }
        sets[index].colors.append(SwatchColor(color: color))
    }

    func removeColor(_ colorID: UUID, from setID: UUID) {
        guard let index = sets.firstIndex(where: { $0.id == setID }) else { return }
        sets[index].colors.removeAll { $0.id == colorID }
    }

    /// Replace an existing swatch's colour in place (keeps its id/position).
    func updateColor(_ colorID: UUID, in setID: UUID, to color: NSColor) {
        guard let setIndex = sets.firstIndex(where: { $0.id == setID }),
              let colorIndex = sets[setIndex].colors.firstIndex(where: { $0.id == colorID }) else { return }
        sets[setIndex].colors[colorIndex].hex = ColorHex.string(from: color)
    }

    /// Update a swatch from a hex string; returns false if the hex is invalid.
    @discardableResult
    func updateColorHex(_ colorID: UUID, in setID: UUID, hex: String) -> Bool {
        guard let color = ColorHex.color(from: hex) else { return false }
        updateColor(colorID, in: setID, to: color)
        return true
    }

    @discardableResult
    func addSet(name: String = "New Set") -> UUID {
        let set = SwatchSet(name: name, colors: [])
        sets.append(set)
        return set.id
    }

    /// Create a new set from a list of colours (e.g. a multi-selection).
    @discardableResult
    func createSet(name: String = "New Set", colors: [NSColor]) -> UUID {
        let set = SwatchSet(name: name, colors: colors.map { SwatchColor(color: $0) })
        sets.append(set)
        return set.id
    }

    func removeSet(_ setID: UUID) {
        // Never delete the base set out from under the tools.
        guard let set = sets.first(where: { $0.id == setID }), !set.isBase else { return }
        sets.removeAll { $0.id == setID }
    }

    func renameSet(_ setID: UUID, to name: String) {
        guard let index = sets.firstIndex(where: { $0.id == setID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sets[index].name = trimmed
    }

    static func defaultBaseSet() -> SwatchSet {
        let hexes = [
            "#000000", "#5B5B5B", "#9B9B9B", "#FFFFFF",
            "#E5484D", "#E5811F", "#F5C518", "#46A758",
            "#12A594", "#3E63DD", "#8E4EC6", "#E93D82"
        ]
        return SwatchSet(name: "Base", colors: hexes.map { SwatchColor(hex: $0) }, isBase: true)
    }
}

/// A compact horizontal strip of the base swatches for quick colour picking.
struct BaseSwatchStrip: View {
    @Environment(\.colorScheme) private var colorScheme
    let colors: [SwatchColor]
    let onPick: (NSColor) -> Void

    var body: some View {
        if !colors.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(colors) { swatch in
                        Button { onPick(swatch.nsColor) } label: {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(swatch.color)
                                .frame(width: 18, height: 18)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.panelFill(colorScheme, 0.22)))
                        }
                        .buttonStyle(.plain)
                        .help(swatch.hex)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }
}

// ColorHex now lives in ImageKidCore (shared by both apps).
