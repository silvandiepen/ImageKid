import AppKit
import SwiftUI

struct TextInspector: View {
    @ObservedObject var session: ImageSession
    let annotationID: UUID

    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Text", systemImage: "textformat")
                    .font(.headline)
                Spacer()
                Button {
                    session.selectedAnnotationID = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close text settings")
            }

            TextEditor(text: textBinding)
                .font(.body)
                .frame(height: 72)
                .padding(6)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Font")
                        .foregroundStyle(.secondary)
                    Picker("Font", selection: fontFamilyBinding) {
                        Text("System").tag("")
                        ForEach(fontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 175)
                }

                GridRow {
                    Text("Size")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Slider(value: fontSizeBinding, in: 8...240, step: 1)
                        Text("\(Int(fontSizeBinding.wrappedValue))")
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                GridRow {
                    Text("Weight")
                        .foregroundStyle(.secondary)
                    Picker("Weight", selection: fontWeightBinding) {
                        ForEach(AnnotationFontWeight.allCases) { weight in
                            Text(weight.label).tag(weight)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                GridRow {
                    Text("Align")
                        .foregroundStyle(.secondary)
                    Picker("Alignment", selection: alignmentBinding) {
                        Image(systemName: "text.alignleft").tag(AnnotationTextAlignment.leading)
                        Image(systemName: "text.aligncenter").tag(AnnotationTextAlignment.center)
                        Image(systemName: "text.alignright").tag(AnnotationTextAlignment.trailing)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                GridRow {
                    Text("Colour")
                        .foregroundStyle(.secondary)
                    ColorPicker("Text colour", selection: colorBinding, supportsOpacity: true)
                        .labelsHidden()
                }
            }

            Divider()

            HStack {
                Button("Delete", role: .destructive) {
                    session.removeAnnotation(id: annotationID)
                }
                Spacer()
                Text("Drag to move · drag corners to resize")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 310)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        )
        .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { session.annotations.first(where: { $0.id == annotationID })?.textValue ?? "" },
            set: { value in
                session.updateAnnotation(id: annotationID) { $0.textValue = value }
            }
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
