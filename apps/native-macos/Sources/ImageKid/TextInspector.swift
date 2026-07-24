import AppKit
import ImageKidCore
import SwiftUI
import ImageKidKit

struct TextInspector: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var library: ColorLibrary
    @ObservedObject var session: ImageSession
    let annotationID: UUID
    @Binding var offset: CGSize
    var dockEdges: (leadingFlat: Bool, trailingFlat: Bool) = (false, false)

    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        FloatingToolPanel(
            title: "Text",
            systemImage: "textformat",
            width: 300,
            offset: $offset,
            onClose: { session.selectedAnnotationID = nil },
            dockEdges: dockEdges
        ) {
            VStack(alignment: .leading, spacing: 18) {
                field("Text") {
                    PlainTextEditor(text: textBinding)
                        .frame(height: 92)
                        .background(
                            Color.panelInk(colorScheme, 0.08),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }

                field("Font") {
                    Picker("Font", selection: fontFamilyBinding) {
                        Text("System").tag("")
                        ForEach(fontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                field("Size") {
                    HStack(spacing: 10) {
                        MinimalSlider(value: fontSizeBinding, in: 0...400, step: 1)
                        TextField("", value: fontSizeBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 52)
                    }
                }

                field("Line height") {
                    HStack(spacing: 10) {
                        MinimalSlider(value: lineHeightBinding, in: 0...4, step: 0.05)
                        TextField("", value: lineHeightBinding, format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 52)
                    }
                }

                Button {
                    session.fitAnnotationToText(id: annotationID)
                } label: {
                    Label("Fit box to text", systemImage: "arrow.down.right.and.arrow.up.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                field("Weight") {
                    Picker("Weight", selection: fontWeightBinding) {
                        ForEach(AnnotationFontWeight.allCases) { weight in
                            Text(weight.label).tag(weight)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                field("Alignment") {
                    Picker("Alignment", selection: alignmentBinding) {
                        Image(systemName: "text.alignleft").tag(AnnotationTextAlignment.leading)
                        Image(systemName: "text.aligncenter").tag(AnnotationTextAlignment.center)
                        Image(systemName: "text.alignright").tag(AnnotationTextAlignment.trailing)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Colour")
                            .font(.caption.weight(.semibold))
                        Text("Text and export colour")
                            .font(.caption2)
                            .foregroundStyle(Color.panelInk(colorScheme, 0.55))
                    }
                    Spacer()
                    ColorPicker("Text colour", selection: colorBinding, supportsOpacity: true)
                        .labelsHidden()
                }

                BaseSwatchStrip(colors: library.baseColors) { colorBinding.wrappedValue = Color(nsColor: $0) }

                Rectangle()
                    .fill(Color.panelFill(colorScheme, 0.09))
                    .frame(height: 1)

                Button(role: .destructive) {
                    session.removeAnnotation(id: annotationID)
                } label: {
                    Label("Delete Text", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("Drag the text to move it. Drag a corner handle to resize it.")
                    .font(.caption)
                    .foregroundStyle(Color.panelInk(colorScheme, 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .darkPanelControl()
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.panelInk(colorScheme, 0.72))
            content()
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { session.annotations.first(where: { $0.id == annotationID })?.textValue ?? "" },
            set: { value in session.updateAnnotation(id: annotationID) { $0.textValue = value } }
        )
    }

    private var fontFamilyBinding: Binding<String> {
        Binding(
            get: { session.annotations.first(where: { $0.id == annotationID })?.fontFamily ?? "" },
            set: { value in session.updateAnnotation(id: annotationID) { $0.fontFamily = value } }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(session.annotations.first(where: { $0.id == annotationID })?.fontSize ?? 48) },
            set: { value in session.updateAnnotation(id: annotationID) { $0.fontSize = CGFloat(value) } }
        )
    }

    private var fontWeightBinding: Binding<AnnotationFontWeight> {
        Binding(
            get: { session.annotations.first(where: { $0.id == annotationID })?.fontWeight ?? .semibold },
            set: { value in session.updateAnnotation(id: annotationID) { $0.fontWeight = value } }
        )
    }

    private var lineHeightBinding: Binding<Double> {
        Binding(
            get: { Double(session.annotations.first(where: { $0.id == annotationID })?.lineHeight ?? 1.1) },
            set: { value in session.updateAnnotation(id: annotationID) { $0.lineHeight = CGFloat(value) } }
        )
    }

    private var alignmentBinding: Binding<AnnotationTextAlignment> {
        Binding(
            get: { session.annotations.first(where: { $0.id == annotationID })?.textAlignment ?? .leading },
            set: { value in session.updateAnnotation(id: annotationID) { $0.textAlignment = value } }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                let color = session.annotations.first(where: { $0.id == annotationID })?.strokeColor ?? .labelColor
                return Color(nsColor: color)
            },
            set: { value in session.updateAnnotation(id: annotationID) { $0.strokeColor = NSColor(value) } }
        )
    }
}
