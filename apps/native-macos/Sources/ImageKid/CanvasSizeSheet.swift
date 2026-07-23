import AppKit
import SwiftUI

/// Change the canvas dimensions (content keeps its pixel size; margin is added
/// or cropped around an anchor). Distinct from Image Size, which resamples.
struct CanvasSizeSheet: View {
    @ObservedObject var appModel: AppModel
    let currentSize: CGSize

    @State private var width: Int
    @State private var height: Int
    @State private var anchor: CanvasAnchor = .center
    @State private var fillEnabled = false
    @State private var fillColor: Color = .white

    init(appModel: AppModel, currentSize: CGSize) {
        self.appModel = appModel
        self.currentSize = currentSize
        _width = State(initialValue: max(1, Int(currentSize.width.rounded())))
        _height = State(initialValue: max(1, Int(currentSize.height.rounded())))
    }

    private let grid: [[CanvasAnchor]] = [
        [.topLeft, .top, .topRight],
        [.left, .center, .right],
        [.bottomLeft, .bottom, .bottomRight]
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Canvas Size").font(.headline)
            Text("Current: \(Int(currentSize.width)) × \(Int(currentSize.height)) px")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                field("Width", $width)
                Text("×").foregroundStyle(.secondary)
                field("Height", $height)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Anchor").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(grid[row]) { a in
                                Button { anchor = a } label: {
                                    Image(systemName: a.symbol)
                                        .frame(width: 30, height: 26)
                                        .background(anchor == a ? Color.accentColor : Color.primary.opacity(0.08),
                                                    in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(anchor == a ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Toggle("Fill new margin", isOn: $fillEnabled)
            if fillEnabled {
                ColorPicker("Fill colour", selection: $fillColor, supportsOpacity: false)
            }

            HStack {
                Button("Cancel") { appModel.isShowingCanvasSize = false }
                Spacer()
                Button("Apply") {
                    appModel.applyCanvasSize(
                        width: width, height: height, anchor: anchor,
                        fill: fillEnabled ? NSColor(fillColor) : nil
                    )
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func field(_ label: String, _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
    }
}
