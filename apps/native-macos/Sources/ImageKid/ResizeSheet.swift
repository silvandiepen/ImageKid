import SwiftUI

struct ResizeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let originalSize: CGSize
    let currentSize: CGSize?
    let apply: (CGSize) -> Void

    @State private var width = ""
    @State private var height = ""
    @State private var lockAspect = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Resize")
                .font(.title2.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Width")
                    TextField("Width", text: $width)
                        .frame(width: 120)
                    Text("px").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Height")
                    TextField("Height", text: $height)
                        .frame(width: 120)
                    Text("px").foregroundStyle(.secondary)
                }
            }

            Toggle("Preserve aspect ratio", isOn: $lockAspect)

            HStack {
                Button("50%") { setScale(0.5) }
                Button("100%") { setScale(1) }
                Button("200%") { setScale(2) }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Resize") {
                    guard let size = parsedSize else { return }
                    apply(size)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedSize == nil)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            let size = currentSize ?? originalSize
            width = String(Int(size.width.rounded()))
            height = String(Int(size.height.rounded()))
        }
        .onChange(of: width) { _, newValue in
            guard lockAspect, let value = Double(newValue), originalSize.width > 0 else { return }
            height = String(Int((value * originalSize.height / originalSize.width).rounded()))
        }
    }

    private var parsedSize: CGSize? {
        guard let widthValue = Double(width), let heightValue = Double(height), widthValue > 0, heightValue > 0 else {
            return nil
        }
        return CGSize(width: widthValue, height: heightValue)
    }

    private func setScale(_ scale: CGFloat) {
        width = String(Int((originalSize.width * scale).rounded()))
        height = String(Int((originalSize.height * scale).rounded()))
    }
}
