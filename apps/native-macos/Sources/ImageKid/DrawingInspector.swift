import AppKit
import SwiftUI
import ImageKidKit

struct DrawingInspector: View {
    @EnvironmentObject private var library: ColorLibrary
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    let onClose: () -> Void

    var body: some View {
        FloatingToolPanel(
            title: selectedDrawable == nil ? "Draw" : "Shape",
            systemImage: "pencil.tip.crop.circle",
            width: 300,
            offset: $offset,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 18) {
                field("Mode") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(DrawingMode.allCases) { mode in
                            modeButton(mode)
                        }
                    }
                }

                field("Stroke") {
                    HStack {
                        ColorPicker("Stroke colour", selection: strokeColorBinding, supportsOpacity: false)
                            .labelsHidden()
                        Spacer()
                        Text("\(Int(lineWidthBinding.wrappedValue)) px")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Slider(value: lineWidthBinding, in: 1...32, step: 1)
                    BaseSwatchStrip(colors: library.baseColors) { strokeColorBinding.wrappedValue = Color(nsColor: $0) }

                    Picker("Style", selection: strokeStyleBinding) {
                        ForEach(ShapeStrokeStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                if modeBinding.wrappedValue == .freehand {
                    field("Brush") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(brushPresets) { preset in
                                brushButton(preset)
                            }
                        }
                    }

                    field("Smoothing") {
                        HStack(spacing: 10) {
                            Image(systemName: "scribble")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.55))
                            Slider(value: $session.drawingSmoothing, in: 0...1, step: 0.05)
                            Text("\(Int(session.drawingSmoothing * 100))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }

                if modeBinding.wrappedValue.supportsFill {
                    field("Fill") {
                        HStack {
                            Toggle(fillEnabledBinding.wrappedValue ? "Colour" : "Transparent", isOn: fillEnabledBinding)
                            Spacer()
                            if fillEnabledBinding.wrappedValue {
                                ColorPicker("Fill colour", selection: fillColorBinding, supportsOpacity: false)
                                    .labelsHidden()
                            }
                        }
                        if fillEnabledBinding.wrappedValue {
                            BaseSwatchStrip(colors: library.baseColors) { fillColorBinding.wrappedValue = Color(nsColor: $0) }
                        }
                    }
                }

                field("Opacity") {
                    HStack(spacing: 10) {
                        Slider(value: opacityBinding, in: 0.05...1, step: 0.05)
                        Text("\(Int(opacityBinding.wrappedValue * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 38, alignment: .trailing)
                    }
                }

                if modeBinding.wrappedValue != .freehand {
                    Toggle("Snap to grid", isOn: $session.snapToGrid)
                        .font(.caption.weight(.medium))
                }

                Text(modeBinding.wrappedValue == .freehand
                     ? "Press and drag to draw a freehand stroke."
                     : "Press and drag on the image to create the selected shape.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                if let selected = selectedDrawable {
                    Rectangle()
                        .fill(.white.opacity(0.09))
                        .frame(height: 1)

                    Button(role: .destructive) {
                        session.removeAnnotation(id: selected.id)
                    } label: {
                        Label("Delete Shape", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .darkPanelControl()
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    /// A freehand brush preset: a named bundle of width/opacity/style/smoothing.
    private struct BrushPreset: Identifiable {
        let id = UUID()
        let name: String
        let symbol: String
        let width: CGFloat
        let opacity: Double
        let style: ShapeStrokeStyle
        let smoothing: Double
    }

    private let brushPresets: [BrushPreset] = [
        BrushPreset(name: "Pen", symbol: "pencil.tip", width: 4, opacity: 1.0, style: .solid, smoothing: 0.2),
        BrushPreset(name: "Marker", symbol: "paintbrush.pointed", width: 14, opacity: 0.9, style: .solid, smoothing: 0.35),
        BrushPreset(name: "Pencil", symbol: "pencil", width: 2, opacity: 0.85, style: .solid, smoothing: 0.1),
        BrushPreset(name: "Highlighter", symbol: "highlighter", width: 24, opacity: 0.32, style: .solid, smoothing: 0.45)
    ]

    private func brushButton(_ preset: BrushPreset) -> some View {
        let isActive = abs(session.drawingLineWidth - preset.width) < 0.5
            && abs(session.drawingOpacity - preset.opacity) < 0.02
            && abs(session.drawingSmoothing - preset.smoothing) < 0.02
        return Button {
            session.drawingLineWidth = preset.width
            session.drawingOpacity = preset.opacity
            session.drawingStrokeStyle = preset.style
            session.drawingSmoothing = preset.smoothing
        } label: {
            HStack(spacing: 7) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(preset.name)
                    .font(.caption.weight(.medium))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                isActive ? Color.accentColor : .white.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help("\(preset.name): \(Int(preset.width)) px, \(Int(preset.opacity * 100))% opacity")
    }

    private var selectedDrawable: Annotation? {
        guard let annotation = session.selectedAnnotation, annotation.isDrawable else { return nil }
        return annotation
    }

    private func modeButton(_ mode: DrawingMode) -> some View {
        Button {
            modeBinding.wrappedValue = mode
        } label: {
            VStack(spacing: 7) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                Text(mode.label)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                modeBinding.wrappedValue == mode ? Color.accentColor : .white.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
            content()
        }
    }

    private var modeBinding: Binding<DrawingMode> {
        Binding(
            get: { selectedDrawable?.drawingMode ?? session.drawingMode },
            set: { mode in
                session.drawingMode = mode
                guard let selected = selectedDrawable else { return }
                session.updateAnnotation(id: selected.id) { $0.changeDrawingMode(mode) }
            }
        )
    }

    private var strokeColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: selectedDrawable?.strokeColor ?? session.drawingStrokeColor)
            },
            set: { value in
                let color = NSColor(value)
                session.drawingStrokeColor = color
                guard let selected = selectedDrawable else { return }
                session.updateAnnotation(id: selected.id) { $0.strokeColor = color }
            }
        )
    }

    private var strokeStyleBinding: Binding<ShapeStrokeStyle> {
        Binding(
            get: { selectedDrawable?.strokeStyle ?? session.drawingStrokeStyle },
            set: { style in
                session.drawingStrokeStyle = style
                guard let selected = selectedDrawable else { return }
                session.updateAnnotation(id: selected.id) { $0.strokeStyle = style }
            }
        )
    }

    private var lineWidthBinding: Binding<Double> {
        Binding(
            get: { Double(selectedDrawable?.lineWidth ?? session.drawingLineWidth) },
            set: { value in
                let width = CGFloat(value)
                session.drawingLineWidth = width
                guard let selected = selectedDrawable else { return }
                session.updateAnnotation(id: selected.id) { $0.lineWidth = width }
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { selectedDrawable?.opacity ?? session.drawingOpacity },
            set: { value in
                session.drawingOpacity = value
                guard let selected = selectedDrawable else { return }
                session.updateAnnotation(id: selected.id) { $0.opacity = value }
            }
        )
    }

    private var fillEnabledBinding: Binding<Bool> {
        Binding(
            get: { (selectedDrawable?.fillColor ?? session.drawingFillColor) != nil },
            set: { enabled in
                let color: NSColor? = enabled ? (selectedDrawable?.fillColor ?? session.drawingFillColor ?? .clear) : nil
                session.drawingFillColor = color
                guard let selected = selectedDrawable else { return }
                session.updateAnnotation(id: selected.id) { $0.fillColor = color }
            }
        )
    }

    private var fillColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: selectedDrawable?.fillColor ?? session.drawingFillColor ?? .clear) },
            set: { value in
                let color = NSColor(value)
                session.drawingFillColor = color
                guard let selected = selectedDrawable else { return }
                session.updateAnnotation(id: selected.id) { $0.fillColor = color }
            }
        )
    }
}
