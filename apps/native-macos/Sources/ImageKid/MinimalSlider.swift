import ImageKidKit
import SwiftUI

/// A thin, tick-free slider that matches the app's dark floating panels — a
/// slim track with a small round knob, replacing the heavier system `Slider`.
struct MinimalSlider<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var value: V
    let range: ClosedRange<V>
    var step: V.Stride?

    init(value: Binding<V>, in range: ClosedRange<V>, step: V.Stride? = nil) {
        self._value = value
        self.range = range
        self.step = step
    }

    private let trackHeight: CGFloat = 4
    private let knob: CGFloat = 15

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let fraction = clampedFraction
            let usable = width - knob
            let knobX = usable * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.panelFill(colorScheme, 0.16))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(knob / 2, knobX + knob / 2), height: trackHeight)

                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: knobX)
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let x = min(max(g.location.x - knob / 2, 0), usable)
                        setValue(fraction: usable > 0 ? x / usable : 0)
                    }
            )
        }
        .frame(height: knob)
    }

    private var clampedFraction: CGFloat {
        let lower = CGFloat(range.lowerBound)
        let upper = CGFloat(range.upperBound)
        guard upper > lower else { return 0 }
        return min(max((CGFloat(value) - lower) / (upper - lower), 0), 1)
    }

    private func setValue(fraction: CGFloat) {
        let lower = CGFloat(range.lowerBound)
        let upper = CGFloat(range.upperBound)
        var raw = lower + fraction * (upper - lower)
        if let step = step, Double(step) > 0 {
            let s = CGFloat(step)
            raw = (raw / s).rounded() * s
        }
        value = V(min(max(raw, lower), upper))
    }
}
