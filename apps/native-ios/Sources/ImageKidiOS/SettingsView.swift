import SwiftUI

/// App settings. Currently the canvas display options, mirroring the macOS app.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Canvas") {
                    Picker("Background", selection: canvasBackgroundBinding) {
                        ForEach(CanvasBackground.allCases) { Text($0.label).tag($0) }
                    }

                    if settings.canvasBackground == .custom {
                        ColorPicker("Colour", selection: customColorBinding, supportsOpacity: false)
                    }

                    Toggle("Show image border", isOn: $settings.showCanvasBorder)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Corner radius \(Int(settings.imageCornerRadius)) pt")
                        Slider(value: $settings.imageCornerRadius, in: 0...28, step: 1)
                    }
                }

                Section("Preview") {
                    canvasPreview
                        .frame(height: 150)
                        .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    /// A live swatch showing how the canvas and image border will look.
    private var canvasPreview: some View {
        ZStack {
            if settings.canvasBackground == .checkerboard {
                CheckerboardPreview()
            } else {
                settings.canvasColor
            }

            RoundedRectangle(cornerRadius: min(settings.imageCornerRadius, 40), style: .continuous)
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    if settings.showCanvasBorder {
                        RoundedRectangle(cornerRadius: min(settings.imageCornerRadius, 40), style: .continuous)
                            .strokeBorder(settings.canvasBorderColor, lineWidth: 1.5)
                    }
                }
                .padding(28)
        }
    }

    private var canvasBackgroundBinding: Binding<CanvasBackground> {
        Binding(get: { settings.canvasBackground }, set: { settings.canvasBackground = $0 })
    }

    private var customColorBinding: Binding<Color> {
        Binding(get: { settings.customCanvasColor }, set: { settings.customCanvasColor = $0 })
    }
}

/// Small checkerboard used inside the settings preview swatch.
private struct CheckerboardPreview: View {
    var square: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let columns = Int((size.width / square).rounded(.up))
            let rows = Int((size.height / square).rounded(.up))
            for row in 0..<max(rows, 1) {
                for column in 0..<max(columns, 1) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)
                    context.fill(Path(rect), with: .color(.gray.opacity(0.18)))
                }
            }
        }
        .background(Color(.secondarySystemBackground))
    }
}
