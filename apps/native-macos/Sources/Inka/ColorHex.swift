import BrushKit
import SwiftUI

/// Hex ⇄ colour helpers for the palette, which the document stores as `#RRGGBB`
/// strings. Kept app-side (the engine's `RGBA` is storage-neutral).
extension RGBA {
    /// Parse `#RRGGBB` / `RRGGBB` (alpha assumed opaque). Returns nil on garbage.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            r: Double((v >> 16) & 0xFF) / 255,
            g: Double((v >> 8) & 0xFF) / 255,
            b: Double(v & 0xFF) / 255)
    }

    /// `#RRGGBB` (clamped, alpha dropped — the palette is opaque swatches).
    var hex: String {
        func c(_ x: Double) -> Int { max(0, min(255, Int((x * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}
