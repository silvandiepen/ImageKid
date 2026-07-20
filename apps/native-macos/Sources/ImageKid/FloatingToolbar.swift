import SwiftUI

struct FloatingToolbar: View {
    @EnvironmentObject private var appModel: AppModel
    let canExport: Bool

    var body: some View {
        HStack(spacing: 7) {
            toolButton(.view)
            toolButton(.select)
            toolButton(.pickColor)
            toolButton(.crop)
            toolButton(.resize)
            toolButton(.draw)
            toolButton(.text)

            Divider().frame(height: 30)

            Button {
                appModel.removeBackground()
            } label: {
                toolbarIcon(
                    appModel.hasRemovedBackground ? "arrow.uturn.backward" : "eraser",
                    selected: appModel.hasRemovedBackground
                )
            }
            .disabled(!appModel.canRemoveBackground)
            .help(appModel.hasRemovedBackground ? "Restore Background" : "Remove Background")
            .accessibilityLabel(appModel.hasRemovedBackground ? "Restore Background" : "Remove Background")

            Menu {
                Button {
                    appModel.requestEnhance()
                } label: {
                    Label("Enhance Image", systemImage: "wand.and.stars")
                }
                Button {
                    appModel.requestPromptEdit()
                } label: {
                    Label("AI Edit…", systemImage: "text.bubble")
                }
            } label: {
                toolbarIcon(
                    "wand.and.stars",
                    selected: appModel.isShowingPromptEdit || appModel.isApplyingPromptEdit
                        || appModel.isShowingEnhance || appModel.isApplyingEnhance
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 42)
            .disabled(appModel.isApplyingPromptEdit || appModel.isApplyingEnhance)
            .help("Magic")
            .accessibilityLabel("Magic")

            Menu {
                Button("Copy Image") {
                    appModel.copyCurrentImageToClipboard()
                }

                if appModel.canCopyImageSelection {
                    Button("Copy Selection") {
                        appModel.copyImageSelectionToClipboard()
                    }
                }

                Divider()

                Button("Save") {
                    appModel.saveImage()
                }

                Button("Export…") {
                    appModel.requestExport()
                }
            } label: {
                toolbarIcon("square.and.arrow.up", selected: false)
            }
            .disabled(!canExport)
            .menuStyle(.borderlessButton)
            .help("Image Actions")
            .accessibilityLabel("Image Actions")
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
    }

    private func toolButton(_ tool: Tool) -> some View {
        Button {
            appModel.activeTool = tool
        } label: {
            toolbarIcon(tool.symbolName, selected: appModel.activeTool == tool)
        }
        .help(tool.label)
        .accessibilityLabel(tool.label)
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
