import AppKit
import SwiftUI
import ImageKidKit

struct DrawingInspector: View {
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
                }

                if modeBinding.wrappedValue.supportsFill {
                    field("Fill") {
                        HStack {
                            Toggle("Enabled", isOn: fillEnabledBinding)
                            Spacer()
                            if fillEnabledBinding.wrappedValue {
                                ColorPicker("Fill colour", selection: fillColorBinding, supportsOpacity: false)
                                    .labelsHidden()
                            }
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
