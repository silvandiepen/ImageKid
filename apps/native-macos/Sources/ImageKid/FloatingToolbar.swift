import ImageKidKit
import SwiftUI

struct FloatingToolbar: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appModel: AppModel
    let canExport: Bool

    @State private var showMagic = false

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

            Button {
                showMagic.toggle()
            } label: {
                toolbarIcon(
                    "wand.and.stars",
                    selected: showMagic || appModel.isShowingPromptEdit || appModel.isApplyingPromptEdit
                        || appModel.isShowingEnhance || appModel.isApplyingEnhance
                )
            }
            .disabled(appModel.isApplyingPromptEdit || appModel.isApplyingEnhance)
            .help("Magic")
            .accessibilityLabel("Magic")
            .popover(isPresented: $showMagic, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    popoverButton("Enhance Image", "wand.and.stars", detail: "Improve detail · upscale") {
                        showMagic = false
                        appModel.requestEnhance()
                    }
                    popoverButton("AI Edit…", "text.bubble", detail: "Describe a change (your API key)") {
                        showMagic = false
                        appModel.requestPromptEdit()
                    }
                }
                .padding(8)
                .frame(width: 260)
            }

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
                toolbarIcon("ellipsis", selected: false)
            }
            .disabled(!canExport)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 42)
            .help("More")
            .accessibilityLabel("More")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(Color.panelFill(colorScheme, 0.14))
        )
        .shadow(color: .black.opacity(0.26), radius: 24, y: 10)
    }

    private func popoverButton(_ title: String, _ symbol: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
