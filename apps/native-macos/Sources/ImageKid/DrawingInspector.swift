import AppKit
import ImageKidCore
import SwiftUI
import ImageKidKit

struct DrawingInspector: View {
    @EnvironmentObject private var library: ColorLibrary
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    var dockEdges: (leadingFlat: Bool, trailingFlat: Bool) = (false, false)
    let onClose: () -> Void

    @State private var showFillPopover = false
    @State private var showBorderPopover = false

    var body: some View {
        FloatingToolPanel(
            title: selectedDrawable == nil ? "Draw" : "Shape",
            systemImage: "pencil.tip.crop.circle",
            width: 300,
            offset: $offset,
            onClose: onClose,
            dockEdges: dockEdges
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if let selected = selectedDrawable {
                    selectedShapeContent(selected)
                } else {
                    drawingDefaultsContent
                }
            }
            .darkPanelControl()
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    // MARK: - Drawing defaults (no shape selected)

    @ViewBuilder
    private var drawingDefaultsContent: some View {
        field("Mode") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(DrawingMode.allCases) { mode in
                    modeButton(mode)
                }
            }
        }

        // Freehand is a brush: show the Brush group right after the mode.
        if modeBinding.wrappedValue == .freehand {
            sectionDivider
            field("Brush") {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(brushPresets) { preset in
                        brushButton(preset)
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "scribble")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                    MinimalSlider(value: $session.drawingSmoothing, in: 0...1, step: 0.05)
                    Text("\(Int(session.drawingSmoothing * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }

        sectionDivider

        field("Stroke") {
            HStack {
                ColorPicker("Stroke colour", selection: strokeColorBinding, supportsOpacity: false)
                    .labelsHidden()
                Spacer()
                Text("\(Int(lineWidthBinding.wrappedValue)) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.58))
            }
            MinimalSlider(value: lineWidthBinding, in: 1...32, step: 1)
            BaseSwatchStrip(colors: library.baseColors) { strokeColorBinding.wrappedValue = Color(nsColor: $0) }

            Picker("Style", selection: strokeStyleBinding) {
                ForEach(ShapeStrokeStyle.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
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

        opacityField

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
    }

    // MARK: - Selected shape: Fill + Border

    @ViewBuilder
    private func selectedShapeContent(_ selected: Annotation) -> some View {
        if selected.isFillable {
            field("Fill") { fillRow }
        }

        field("Border") { borderRow(selected) }

        field("Blend mode") {
            Picker("Blend mode", selection: blendModeBinding) {
                ForEach(ShapeBlendMode.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        opacityField

        Toggle("Snap to grid", isOn: $session.snapToGrid)
            .font(.caption.weight(.medium))

        Rectangle().fill(.white.opacity(0.09)).frame(height: 1)

        Button(role: .destructive) {
            session.removeAnnotation(id: selected.id)
        } label: {
            Label("Delete Shape", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var opacityField: some View {
        field("Opacity") {
            HStack(spacing: 10) {
                MinimalSlider(value: opacityBinding, in: 0.05...1, step: 0.05)
                Text("\(Int(opacityBinding.wrappedValue * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
            }
        }
    }

    // MARK: Fill row + popover

    private var fillRow: some View {
        Button {
            showFillPopover = true
        } label: {
            HStack(spacing: 10) {
                colorWell(fillEnabledBinding.wrappedValue ? fillColorBinding.wrappedValue : nil)
                Text(fillEnabledBinding.wrappedValue ? fillColorBinding.wrappedValue.hexLabel : "Transparent")
                    .font(.caption.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showFillPopover, arrowEdge: .leading) {
            fillPopover
        }
    }

    private var fillPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fill").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                ColorPicker("Fill colour", selection: fillColorBinding, supportsOpacity: true)
                    .labelsHidden()
            }

            // Swatches, with a transparent option as the first dot.
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 24, maximum: 30), spacing: 5)], spacing: 5) {
                    Button { fillEnabledBinding.wrappedValue = false } label: {
                        transparentSwatch(selected: !fillEnabledBinding.wrappedValue)
                    }
                    .buttonStyle(.plain)
                    .help("No fill (transparent)")

                    ForEach(library.sets) { set in
                        ForEach(set.colors) { swatch in
                            Button { fillColorBinding.wrappedValue = Color(nsColor: swatch.nsColor) } label: {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(swatch.color)
                                    .frame(height: 24)
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.2)))
                            }
                            .buttonStyle(.plain)
                            .help(swatch.hex)
                        }
                    }
                }
            }
            .frame(maxHeight: 108)

            if fillEnabledBinding.wrappedValue {
                field("Opacity") {
                    labeledSlider(value: fillOpacityBinding, range: 0...1, step: 0.01, suffix: "%", percent: true)
                }
            }
        }
        .padding(14)
        .frame(width: 248)
    }

    private func transparentSwatch(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(height: 24)
            .overlay(
                Image(systemName: "circle.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            )
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selected ? Color.accentColor : .white.opacity(0.25), lineWidth: selected ? 2 : 1))
    }

    /// Swatches from every set in the library (base first), for quick picking.
    private func paletteSwatches(_ pick: @escaping (NSColor) -> Void) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 24, maximum: 30), spacing: 5)], spacing: 5) {
                ForEach(library.sets) { set in
                    ForEach(set.colors) { swatch in
                        Button { pick(swatch.nsColor) } label: {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(swatch.color)
                                .frame(height: 24)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .help(swatch.hex)
                    }
                }
            }
        }
        .frame(maxHeight: 108)
    }

    // MARK: Border row + popover

    private func borderRow(_ selected: Annotation) -> some View {
        Button {
            showBorderPopover = true
        } label: {
            HStack(spacing: 10) {
                colorWell(strokeColorBinding.wrappedValue)
                Text("\(Int(lineWidthBinding.wrappedValue)) px · \(strokeStyleBinding.wrappedValue.label)")
                    .font(.caption.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showBorderPopover, arrowEdge: .leading) {
            borderPopover(selected)
        }
    }

    private func borderPopover(_ selected: Annotation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                field("Stroke colour") {
                    ColorPicker("Stroke colour", selection: strokeColorBinding, supportsOpacity: true).labelsHidden()
                    paletteSwatches { strokeColorBinding.wrappedValue = Color(nsColor: $0) }
                }
                field("Width") {
                    labeledSlider(value: lineWidthBinding, range: 0...64, step: 1, suffix: "px")
                }
                field("Stroke opacity") {
                    labeledSlider(value: strokeOpacityBinding, range: 0...1, step: 0.01, suffix: "%", percent: true)
                }
                field("Style") {
                    Picker("Style", selection: strokeStyleBinding) {
                        ForEach(ShapeStrokeStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented)
                }
                field("Dash") {
                    labeledSlider(value: dashLengthBinding, range: 0...80, step: 1, suffix: "size")
                    labeledSlider(value: dashGapBinding, range: 0...80, step: 1, suffix: "gap")
                    labeledSlider(value: dashOffsetBinding, range: 0...80, step: 1, suffix: "offset")
                    Text("Dash size 0 uses the style preset above.")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
                if selected.isRectangle {
                    field("Rounded corners") {
                        labeledSlider(value: uniformCornerBinding, range: 0...400, step: 1, suffix: "all")
                        HStack(spacing: 8) {
                            cornerField("TL", perCornerBinding(0))
                            cornerField("TR", perCornerBinding(1))
                        }
                        HStack(spacing: 8) {
                            cornerField("BL", perCornerBinding(3))
                            cornerField("BR", perCornerBinding(2))
                        }
                    }
                }
                field("Alignment") {
                    Picker("Alignment", selection: strokeAlignmentBinding) {
                        ForEach(StrokeAlignment.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented)
                }
            }
            .padding(14)
        }
        .frame(width: 268, height: 380)
    }

    /// Thin divider that visually separates the Draw / Brush / Stroke groups.
    private var sectionDivider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
    }

    private func cornerField(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.55)).frame(width: 20, alignment: .leading)
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Uniform radius: sets all four and clears any per-corner override.
    private var uniformCornerBinding: Binding<Double> {
        Binding(
            get: { Double(selectedDrawable?.cornerRadius ?? 0) },
            set: { value in
                guard let id = selectedDrawable?.id else { return }
                session.updateAnnotation(id: id) {
                    $0.cornerRadius = CGFloat(value)
                    $0.cornerRadii = nil
                }
            }
        )
    }

    private func perCornerBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard let a = selectedDrawable else { return 0 }
                if let radii = a.cornerRadii, radii.count == 4 { return Double(radii[index]) }
                return Double(a.cornerRadius)
            },
            set: { value in
                guard let a = selectedDrawable else { return }
                session.updateAnnotation(id: a.id) { annotation in
                    var radii = annotation.cornerRadii ?? Array(repeating: annotation.cornerRadius, count: 4)
                    if radii.count != 4 { radii = Array(repeating: annotation.cornerRadius, count: 4) }
                    radii[index] = max(0, CGFloat(value))
                    annotation.cornerRadii = radii
                }
            }
        )
    }

    private func labeledSlider(value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String, percent: Bool = false) -> some View {
        HStack(spacing: 10) {
            MinimalSlider(value: value, in: range, step: step)
            Text(percent ? "\(Int(value.wrappedValue * 100))\(suffix)" : "\(Int(value.wrappedValue)) \(suffix)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 62, alignment: .trailing)
        }
    }

    private func colorWell(_ color: Color?) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color ?? .clear)
            .frame(width: 24, height: 24)
            .overlay {
                if color == nil {
                    // Transparent: checker + slash.
                    Image(systemName: "circle.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.25)))
    }

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
                Color(nsColor: selectedDrawable?.strokeColor ?? library.foreground)
            },
            set: { value in
                let color = NSColor(value)
                session.drawingStrokeColor = color
                if let selected = selectedDrawable {
                    session.updateAnnotation(id: selected.id) { $0.strokeColor = color }
                } else {
                    // No selection: this is the default draw colour = foreground.
                    library.foreground = color
                }
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

    private var blendModeBinding: Binding<ShapeBlendMode> {
        Binding(
            get: { selectedDrawable?.blendMode ?? session.drawingBlendMode },
            set: { value in
                session.drawingBlendMode = value
                guard let selected = selectedDrawable else { return }
                session.updateAnnotation(id: selected.id) { $0.blendMode = value }
            }
        )
    }

    /// Opacity (0…1) of the stroke colour's alpha channel.
    private var strokeOpacityBinding: Binding<Double> {
        Binding(
            get: { Double((selectedDrawable?.strokeColor ?? library.foreground).alphaComponent) },
            set: { value in
                let a = CGFloat(value)
                let base = (selectedDrawable?.strokeColor ?? library.foreground)
                let color = base.withAlphaComponent(a)
                session.drawingStrokeColor = color
                if let selected = selectedDrawable {
                    session.updateAnnotation(id: selected.id) { $0.strokeColor = color }
                } else {
                    library.foreground = color
                }
            }
        )
    }

    /// Opacity (0…1) of the fill colour's alpha channel.
    private var fillOpacityBinding: Binding<Double> {
        Binding(
            get: { Double((selectedDrawable?.fillColor ?? session.drawingFillColor)?.alphaComponent ?? 1) },
            set: { value in
                let a = CGFloat(value)
                let base = (selectedDrawable?.fillColor ?? session.drawingFillColor ?? .white)
                let color = base.withAlphaComponent(a)
                session.drawingFillColor = color
                guard let selected = selectedDrawable else { return }
                session.updateAnnotation(id: selected.id) { $0.fillColor = color }
            }
        )
    }

    private var strokeAlignmentBinding: Binding<StrokeAlignment> {
        Binding(
            get: { selectedDrawable?.strokeAlignment ?? session.drawingStrokeAlignment },
            set: { value in
                session.drawingStrokeAlignment = value
                guard let selected = selectedDrawable else { return }
                session.updateAnnotation(id: selected.id) { $0.strokeAlignment = value }
            }
        )
    }

    private var cornerRadiusBinding: Binding<Double> {
        shapeMetricBinding(get: { $0.cornerRadius }, sessionGet: { $0.drawingCornerRadius },
                           set: { $0.cornerRadius = $1 }, sessionSet: { $0.drawingCornerRadius = $1 })
    }

    private var dashLengthBinding: Binding<Double> {
        shapeMetricBinding(get: { $0.dashLength }, sessionGet: { $0.drawingDashLength },
                           set: { $0.dashLength = $1 }, sessionSet: { $0.drawingDashLength = $1 })
    }

    private var dashGapBinding: Binding<Double> {
        shapeMetricBinding(get: { $0.dashGap }, sessionGet: { $0.drawingDashGap },
                           set: { $0.dashGap = $1 }, sessionSet: { $0.drawingDashGap = $1 })
    }

    private var dashOffsetBinding: Binding<Double> {
        shapeMetricBinding(get: { $0.dashOffset }, sessionGet: { $0.drawingDashOffset },
                           set: { $0.dashOffset = $1 }, sessionSet: { $0.drawingDashOffset = $1 })
    }

    /// Builds a Double binding for a CGFloat shape metric that also writes the
    /// session drawing default.
    private func shapeMetricBinding(
        get: @escaping (Annotation) -> CGFloat,
        sessionGet: @escaping (ImageSession) -> CGFloat,
        set: @escaping (inout Annotation, CGFloat) -> Void,
        sessionSet: @escaping (ImageSession, CGFloat) -> Void
    ) -> Binding<Double> {
        Binding(
            get: { Double(selectedDrawable.map(get) ?? sessionGet(session)) },
            set: { value in
                let v = CGFloat(value)
                sessionSet(session, v)
                guard let selected = selectedDrawable else { return }
                session.updateAnnotation(id: selected.id) { set(&$0, v) }
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

private extension Color {
    /// Short hex label (e.g. "#E5484D") for display in the inspector.
    var hexLabel: String { ColorHex.string(from: NSColor(self)) }
}
