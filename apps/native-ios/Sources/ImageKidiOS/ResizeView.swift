import SwiftUI

/// Resize editor: exact width/height with optional aspect lock, plus percentage
/// presets. Reports the chosen pixel size via `onApply`.
struct ResizeView: View {
    let pixelSize: CGSize
    let onApply: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var width: Int
    @State private var height: Int
    @State private var lockAspect = true

    private let aspect: CGFloat

    init(pixelSize: CGSize, onApply: @escaping (Int, Int) -> Void) {
        self.pixelSize = pixelSize
        self.onApply = onApply
        _width = State(initialValue: max(1, Int(pixelSize.width.rounded())))
        _height = State(initialValue: max(1, Int(pixelSize.height.rounded())))
        aspect = pixelSize.width / max(pixelSize.height, 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dimensions") {
                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("Width", value: $width, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .onChange(of: width) { _, newValue in
                                if lockAspect {
                                    height = max(1, Int((CGFloat(newValue) / aspect).rounded()))
                                }
                            }
                        Text("px").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("Height", value: $height, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .disabled(lockAspect)
                            .foregroundStyle(lockAspect ? .secondary : .primary)
                        Text("px").foregroundStyle(.secondary)
                    }
                    Toggle("Lock aspect ratio", isOn: $lockAspect)
                        .onChange(of: lockAspect) { _, locked in
                            if locked { height = max(1, Int((CGFloat(width) / aspect).rounded())) }
                        }
                }

                Section("Scale") {
                    HStack(spacing: 8) {
                        ForEach([25, 50, 75, 200], id: \.self) { percent in
                            Button("\(percent)%") { applyPercent(percent) }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                Section {
                    Text("Original \(Int(pixelSize.width.rounded())) × \(Int(pixelSize.height.rounded())) px")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Resize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") { onApply(max(1, width), max(1, height)); dismiss() }.bold()
                }
            }
        }
    }

    private func applyPercent(_ percent: Int) {
        let factor = CGFloat(percent) / 100
        width = max(1, Int((pixelSize.width * factor).rounded()))
        height = max(1, Int((pixelSize.height * factor).rounded()))
    }
}
