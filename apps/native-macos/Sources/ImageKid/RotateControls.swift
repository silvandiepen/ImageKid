import SwiftUI

struct RotateControls: View {
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        FloatingToolPanel(
            title: "Rotate",
            systemImage: "rotate.right",
            width: 300,
            offset: $offset,
            onClose: onCancel
        ) {
            VStack(alignment: .leading, spacing: 16) {
                field("Quick") {
                    HStack(spacing: 7) {
                        quickButton("rotate.left", active: false) {
                            session.rotationDraft = normalized(session.rotationDraft - 90)
                        }
                        quickButton("rotate.right", active: false) {
                            session.rotationDraft = normalized(session.rotationDraft + 90)
                        }
                        quickButton("arrow.left.and.right", active: session.rotationFlipHorizontal) {
                            session.rotationFlipHorizontal.toggle()
                        }
                        quickButton("arrow.up.and.down", active: session.rotationFlipVertical) {
                            session.rotationFlipVertical.toggle()
                        }
                    }
                }

                field("Angle") {
                    HStack(spacing: 8) {
                        Slider(value: $session.rotationDraft, in: -180...180, step: 1)
                        TextField("Angle", value: $session.rotationDraft, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 58)
                        Text("°").foregroundStyle(.white.opacity(0.55))
                    }

                    Button {
                        session.rotationDraft = 0
                    } label: {
                        Label("Straighten", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(session.rotationDraft == 0)
                }

                Toggle("Resize canvas to fit", isOn: $session.rotationResizesCanvas)
                Toggle("Fill empty space", isOn: $session.rotationFillsGaps)

                if session.rotationFillsGaps {
                    HStack {
                        Text("Fill colour")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                        Spacer()
                        ColorPicker("", selection: fillColorBinding, supportsOpacity: false)
                            .labelsHidden()
                    }
                    Text("AI “magic” fill is coming next — solid colour for now.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Apply Rotation", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!session.hasRotationEdits)

                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .darkPanelControl()
        }
    }

    private func quickButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(maxWidth: .infinity, minHeight: 22)
        }
        .buttonStyle(.bordered)
        .tint(active ? .accentColor : nil)
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

    private var fillColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: session.rotationFillColor) },
            set: { session.rotationFillColor = NSColor($0) }
        )
    }

    private func normalized(_ angle: Double) -> Double {
        var value = angle.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}
