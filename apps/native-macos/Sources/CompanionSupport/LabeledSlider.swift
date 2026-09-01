import SwiftUI

/// A slider that says what it is and what it is set to, in one compact block.
struct LabeledSlider: View {
    let title: String
    let reading: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Text(reading).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Slider(value: $value, in: range)
        }
    }
}
