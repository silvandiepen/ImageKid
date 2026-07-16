import SwiftUI

struct FloatingToolbar: View {
    @EnvironmentObject private var appModel: AppModel
    let canExport: Bool

    var body: some View {
        HStack(spacing: 4) {
            toolButton(.view)
            toolButton(.pickColor)
            toolButton(.crop)

            Menu {
                Button("Rectangle") { appModel.activeTool = .rectangle }
                Button("Text") { appModel.activeTool = .text }
            } label: {
                Label("Annotate", systemImage: "pencil.and.outline")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 20)

            Button {
                appModel.isShowingResize = true
            } label: {
                Label("Resize", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Button {
                appModel.exportImage()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(!canExport)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(radius: 12, y: 4)
        .help("ImageKid tools")
    }

    private func toolButton(_ tool: Tool) -> some View {
        Button {
            appModel.activeTool = tool
        } label: {
            Image(systemName: tool.symbolName)
                .frame(width: 28, height: 28)
                .background(
                    appModel.activeTool == tool ? Color.accentColor.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .help(tool.label)
    }
}
