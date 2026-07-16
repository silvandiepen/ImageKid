import SwiftUI

struct FloatingToolbar: View {
    @EnvironmentObject private var appModel: AppModel
    let canExport: Bool

    var body: some View {
        HStack(spacing: 7) {
            toolButton(.view)
            toolButton(.pickColor)
            toolButton(.crop)
            toolButton(.draw)
            toolButton(.text)

            Divider().frame(height: 30)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        )
        .shadow(color: .black.opacity(0.26), radius: 24, y: 10)
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
            .font(.system(size: 19, weight: selected ? .semibold : .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(selected ? Color.white : .primary)
            .frame(width: 42, height: 42)
            .background(
                selected ? Color.accentColor : Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
