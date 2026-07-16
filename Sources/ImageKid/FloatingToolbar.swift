import SwiftUI

struct FloatingToolbar: View {
    @EnvironmentObject private var appModel: AppModel
    let canExport: Bool

    var body: some View {
        HStack(spacing: 7) {
            toolButton(.view)
            toolButton(.pickColor)
            toolButton(.crop)

            Menu {
                Button("Rectangle") { appModel.activeTool = .rectangle }
                Button("Text") { appModel.activeTool = .text }
            } label: {
                toolbarIcon(
                    "pencil.and.outline",
                    selected: appModel.activeTool == .rectangle || appModel.activeTool == .text
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Annotate")

            Divider().frame(height: 28)

            Button {
                appModel.isShowingResize = true
            } label: {
                toolbarIcon("arrow.up.left.and.arrow.down.right", selected: false)
            }
            .help("Resize")

            Button {
                appModel.requestExport()
            } label: {
                toolbarIcon("square.and.arrow.up", selected: false)
            }
            .disabled(!canExport)
            .help("Export")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        )
        .shadow(color: .black.opacity(0.24), radius: 22, y: 9)
        .help("ImageKid tools")
    }

    private func toolButton(_ tool: Tool) -> some View {
        Button {
            appModel.activeTool = tool
        } label: {
            toolbarIcon(tool.symbolName, selected: appModel.activeTool == tool)
        }
        .help(tool.label)
    }

    private func toolbarIcon(_ symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: selected ? .semibold : .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(selected ? Color.white : .primary)
            .frame(width: 39, height: 39)
            .background(
                selected ? Color.accentColor : Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
