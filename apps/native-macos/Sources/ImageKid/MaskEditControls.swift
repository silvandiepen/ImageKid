import SwiftUI
import ImageKidKit

/// Controls for editing the selected layer's mask: how it's shown, and the
/// brush / magic-wand used to paint it.
struct MaskEditControls: View {
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    let onDone: () -> Void

    var body: some View {
        FloatingToolPanel(
            title: "Edit Mask",
            systemImage: "theatermask.and.paintbrush",
            width: 300,
            offset: $offset,
            onClose: onDone
        ) {
            VStack(alignment: .leading, spacing: 16) {
                field("Show mask as") {
                    Picker("View", selection: $session.maskViewMode) {
                        ForEach(MaskViewMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
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
                            Slider(value: $session.maskWandTolerance, in: 0.01...0.6, step: 0.01)
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
                    field("Size") {
                        HStack(spacing: 10) {
                            Slider(value: $session.maskBrushSize, in: 4...240, step: 1)
                            Text("\(Int(session.maskBrushSize))")
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                    field("Softness") {
                        Slider(value: $session.maskBrushSoftness, in: 0...0.9, step: 0.05)
                    }
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
}
