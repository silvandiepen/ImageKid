import SwiftUI
import ImageKidKit

/// Controls for editing the selected layer's mask: how it's shown, and the
/// brush / magic-wand used to paint it.
struct MaskEditControls: View {
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    var dockEdges: (leadingFlat: Bool, trailingFlat: Bool) = (false, false)
    let onDone: () -> Void

    var body: some View {
        FloatingToolPanel(
            title: "Edit Mask",
            systemImage: "theatermask.and.paintbrush",
            width: 300,
            offset: $offset,
            onClose: onDone,
            dockEdges: dockEdges
        ) {
            VStack(alignment: .leading, spacing: 16) {
                field("Mask view") {
                    HStack(spacing: 10) {
                        MinimalSlider(value: $session.maskViewOpacity, in: 0...1, step: 0.01)
                        Text("\(Int(session.maskViewOpacity * 100))%")
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                field("Tool") {
                    Picker("Tool", selection: Binding(
                        get: { session.maskWandMode ? 1 : 0 },
                        set: { session.maskWandMode = ($0 == 1) }
                    )) {
                        Text("Brush").tag(0)
                        Text("Magic Wand").tag(1)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                if session.maskWandMode {
                    field("Tolerance") {
                        HStack(spacing: 10) {
                            MinimalSlider(value: $session.maskWandTolerance, in: 0.01...0.6, step: 0.01)
                            Text("\(Int(session.maskWandTolerance * 100))%")
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    Text("Click a region to hide it. Hold to keep clicking.")
                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    field("Brush") {
                        Picker("Brush", selection: Binding(
                            get: { session.maskBrushReveal ? 1 : 0 },
                            set: { session.maskBrushReveal = ($0 == 1) }
                        )) {
                            Text("Hide").tag(0)
                            Text("Reveal").tag(1)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    valueSlider("Size", value: $session.maskBrushSize, range: 4...400, step: 1, suffix: "px")
                    valueSlider("Hardness", value: hardnessBinding, range: 0...1, step: 0.01, percent: true)
                    valueSlider("Spacing", value: $session.maskBrushSpacing, range: 0.02...1, step: 0.01, percent: true)
                    valueSlider("Opacity", value: $session.maskBrushOpacity, range: 0.05...1, step: 0.01, percent: true)
                    valueSlider("Roundness", value: $session.maskBrushRoundness, range: 0.1...1, step: 0.01, percent: true)
                    if session.maskBrushRoundness < 0.999 {
                        valueSlider("Angle", value: $session.maskBrushAngle, range: 0...360, step: 1, suffix: "°")
                    }

                    brushPreview
                }

                Rectangle().fill(.white.opacity(0.09)).frame(height: 1)

                HStack {
                    if let id = session.maskEditLayerID {
                        Button("Delete Mask", role: .destructive) {
                            session.removeLayerMask(id: id)
                            onDone()
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button("Done") { session.recordMaskEdit(); onDone() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .darkPanelControl()
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
            content()
        }
    }

    private var hardnessBinding: Binding<Double> {
        Binding(
            get: { Double(1 - session.maskBrushSoftness) },
            set: { session.maskBrushSoftness = 1 - CGFloat($0) }
        )
    }

    private func valueSlider<V: BinaryFloatingPoint>(
        _ title: String, value: Binding<V>, range: ClosedRange<V>, step: V.Stride,
        suffix: String = "", percent: Bool = false
    ) -> some View where V.Stride: BinaryFloatingPoint {
        field(title) {
            HStack(spacing: 10) {
                MinimalSlider(value: value, in: range, step: step)
                Text(readout(Double(value.wrappedValue), suffix: suffix, percent: percent))
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func readout(_ v: Double, suffix: String, percent: Bool) -> String {
        if percent { return "\(Int((v * 100).rounded()))%" }
        if suffix == "°" { return "\(Int(v.rounded()))°" }
        return suffix.isEmpty ? "\(Int(v.rounded()))" : "\(Int(v.rounded())) \(suffix)"
    }

    /// Small live preview of the current brush shape/softness.
    private var brushPreview: some View {
        let hardness = 1 - Double(session.maskBrushSoftness)
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
            Ellipse()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [Color.white, Color.white.opacity(0)]),
                    center: .center,
                    startRadius: 26 * hardness,
                    endRadius: 28
                ))
                .frame(width: 56, height: 56 * session.maskBrushRoundness)
                .rotationEffect(.degrees(session.maskBrushAngle))
                .opacity(session.maskBrushOpacity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
    }
}
