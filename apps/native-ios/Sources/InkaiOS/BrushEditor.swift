import BrushKit
import SwiftUI

/// The brush editor controls (iPad) — the content that exposes the engine's
/// depth. Every control binds to the model's working `brush`, and a live preview
/// re-renders through BrushKit's reference renderer on each change. Save / Load
/// flip the model's file-picker flags (handled by `ContentView`). Hosted inside
/// the shared `FloatingToolPanel` by `InkaBrushPanel`. Mirrors the macOS editor.
struct BrushEditorControls: View {
    @ObservedObject var model: InkaModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                BrushPreview(brush: model.brush)
                    .frame(height: 90)
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 8))

                group("Brush") {
                    slider("Size", value: sizeBinding, range: 1...300, unit: "pt")
                    slider("Flow", value: bind(\.flow), range: 0...1)
                    slider("Opacity", value: bind(\.opacity), range: 0...1)
                    slider("Smoothing", value: bind(\.smoothing), range: 0...1)
                }

                group("Tip") {
                    Picker("Shape", selection: shapeBinding) {
                        ForEach(Brush.Shape.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    slider("Hardness", value: bindTip(\.hardness), range: 0...1)
                    slider("Roundness", value: bindTip(\.roundness), range: 0.05...1)
                    slider("Angle", value: bindTip(\.angle), range: 0...(.pi))
                    slider("Spacing", value: bindTip(\.spacing), range: 0.02...0.5)
                    slider("Scatter", value: bindTip(\.scatter), range: 0...1)
                }

                group("Dynamics") {
                    Picker("Pressure curve", selection: bindCurve(\.pressureCurve)) {
                        ForEach(ResponseCurve.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    slider("Pressure → Size", value: bindDyn(\.pressureToSize), range: 0...1)
                    slider("Pressure → Opacity", value: bindDyn(\.pressureToOpacity), range: 0...1)
                    slider("Velocity → Size", value: bindDyn(\.velocityToSize), range: 0...1)
                    slider("Tilt → Size", value: bindDyn(\.tiltToSize), range: 0...1)
                    slider("Tilt → Angle", value: bindDyn(\.tiltToAngle), range: 0...1)
                    slider("Size jitter", value: bindDyn(\.sizeJitter), range: 0...1)
                    slider("Angle jitter", value: bindDyn(\.angleJitter), range: 0...1)
                    slider("Hue jitter", value: bindDyn(\.hueJitter), range: 0...1)
                }

                group("Grain (paper tooth)") {
                    slider("Depth", value: bindGrain(\.depth), range: 0...1)
                    slider("Scale", value: bindGrain(\.scale), range: 0.2...4)
                }

                group("Taper") {
                    slider("Start length", value: bindTaper(\.startLength), range: 0...60, unit: "pt")
                    slider("End length", value: bindTaper(\.endLength), range: 0...60, unit: "pt")
                }
            }
        }
    }

    private var header: some View {
        HStack {
            TextField("Brush name", text: bind(\.name))
                .textFieldStyle(.roundedBorder)
            Button { model.brushExportRequested = true } label: {
                Image(systemName: "square.and.arrow.down")
            }
            Button { model.brushImportRequested = true } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func slider(
        _ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = ""
    ) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 118, alignment: .leading)
            Slider(value: value, in: range)
            Text(unit.isEmpty ? String(format: "%.2f", value.wrappedValue)
                : "\(Int(value.wrappedValue))")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - Bindings into the working brush

    private var sizeBinding: Binding<Double> { bind(\.size) }
    private var shapeBinding: Binding<Brush.Shape> {
        Binding(get: { model.brush.tip.shape }, set: { model.brush.tip.shape = $0 })
    }

    private func bind<V>(_ kp: WritableKeyPath<Brush, V>) -> Binding<V> {
        Binding(get: { model.brush[keyPath: kp] }, set: { model.brush[keyPath: kp] = $0 })
    }
    private func bindTip(_ kp: WritableKeyPath<Brush.Tip, Double>) -> Binding<Double> {
        Binding(get: { model.brush.tip[keyPath: kp] }, set: { model.brush.tip[keyPath: kp] = $0 })
    }
    private func bindDyn(_ kp: WritableKeyPath<Brush.Dynamics, Double>) -> Binding<Double> {
        Binding(
            get: { model.brush.dynamics[keyPath: kp] },
            set: { model.brush.dynamics[keyPath: kp] = $0 })
    }
    private func bindCurve(_ kp: WritableKeyPath<Brush.Dynamics, ResponseCurve>) -> Binding<ResponseCurve> {
        Binding(
            get: { model.brush.dynamics[keyPath: kp] },
            set: { model.brush.dynamics[keyPath: kp] = $0 })
    }
    private func bindGrain(_ kp: WritableKeyPath<Brush.Grain, Double>) -> Binding<Double> {
        Binding(get: { model.brush.grain[keyPath: kp] }, set: { model.brush.grain[keyPath: kp] = $0 })
    }
    private func bindTaper(_ kp: WritableKeyPath<Brush.Taper, Double>) -> Binding<Double> {
        Binding(get: { model.brush.taper[keyPath: kp] }, set: { model.brush.taper[keyPath: kp] = $0 })
    }
}

/// A live preview of a brush: a pressure-swelling S-curve rendered through
/// BrushKit's reference renderer. Cheap enough to redraw on every edit.
struct BrushPreview: View {
    let brush: Brush

    var body: some View {
        Canvas { context, size in
            guard let cg = Self.render(brush: brush, size: size) else { return }
            context.draw(Image(decorative: cg, scale: 1), in: CGRect(origin: .zero, size: size))
        }
    }

    private static func render(brush: Brush, size: CGSize) -> CGImage? {
        guard size.width > 4, size.height > 4 else { return nil }
        let w = size.width
        let h = size.height
        var samples: [StrokeSample] = []
        let n = 48
        for i in 0...n {
            let t = Double(i) / Double(n)
            samples.append(
                StrokeSample(
                    position: CGPoint(x: 12 + t * (w - 24), y: h / 2 + sin(t * .pi * 2) * (h * 0.22)),
                    pressure: max(0.06, sin(t * .pi)), timestamp: t * 0.4))
        }
        return ReferenceRenderer.render(
            stroke: StrokeInput(samples: samples), brush: brush,
            color: RGBA(r: 0.92, g: 0.93, b: 0.96), size: size, seed: 7)
    }
}
