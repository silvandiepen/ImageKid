import SwiftUI

/// The palettes' numeric text field: commits on Return like a plain
/// TextField, and steps with the arrow keys — ↑/↓ ±1, ⇧↑/⇧↓ ±10 — with
/// every step committing like a typed edit (Illustrator field behaviour).
/// One reusable component swapped in everywhere instead of per-field hacks.
struct NumericField: View {
    var placeholder: String = "—"
    @Binding var text: String
    /// The ↑/↓ step; ⇧ multiplies it by 10.
    var step: Double = 1
    /// Clamp applied to STEPPED values (typed values stay the caller's
    /// business — commit handlers already validate).
    var range: ClosedRange<Double>? = nil
    /// Called after Return and after every arrow step, with the parsed
    /// value; the field's text is already updated when it runs.
    var onCommit: (Double) -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospaced())
            .onSubmit {
                if let v = Double(text.trimmingCharacters(in: .whitespaces)) {
                    onCommit(v)
                }
            }
            .numericArrowKeys(text: $text, step: step, range: range, onStep: onCommit)
    }

    /// Field formatting: integers bare, fractions to two places.
    static func format(_ v: Double) -> String {
        let rounded = (v * 100).rounded() / 100
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.2f", rounded)
    }
}

extension View {
    /// Arrow-key stepping for a numeric text field that keeps its OWN
    /// styling and commit flow (settings forms, prompt-backed fields):
    /// ↑/↓ step ±`step`, ⇧ multiplies by 10; the field's text updates and
    /// `onStep` runs with the new value.
    func numericArrowKeys(
        text: Binding<String>, step: Double = 1, range: ClosedRange<Double>? = nil,
        onStep: @escaping (Double) -> Void = { _ in }
    ) -> some View {
        onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
            let base = Double(text.wrappedValue.trimmingCharacters(in: .whitespaces)) ?? 0
            let magnitude = press.modifiers.contains(.shift) ? step * 10 : step
            var v = base + (press.key == .upArrow ? magnitude : -magnitude)
            if let range {
                v = min(max(v, range.lowerBound), range.upperBound)
            }
            text.wrappedValue = NumericField.format(v)
            onStep(v)
            return .handled
        }
    }
}
