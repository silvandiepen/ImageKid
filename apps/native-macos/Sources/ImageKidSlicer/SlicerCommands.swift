import SwiftUI

/// Menu commands. Everything the canvas can do by pointer is also here, so the
/// workflow is discoverable and reachable from the keyboard.
struct SlicerCommands: Commands {
    @ObservedObject var model: SlicerDocumentModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Image…") { model.openImage() }
                .keyboardShortcut("o")

            Button("Open Session…") { model.openSession() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Slices…") { model.save() }
                .keyboardShortcut("s")
                .disabled(!model.canSave)

            Button("Save Session…") { model.saveSession() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!model.canSaveSession)

            Button("Export All Images…") { model.exportAll() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!model.canExportAll)

            Divider()

            Button("Close Image") { model.closeCurrentImage() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!model.hasSource)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Copy Slice") { model.copySelectedSliceToClipboard() }
                .keyboardShortcut("c")
                .disabled(!model.canCopySelectedSlice)

            Button("Paste Image") { model.pasteImage() }
                .keyboardShortcut("v")

            Divider()

            Button("Duplicate Slice") { model.duplicateSelectedSlice() }
                .keyboardShortcut("d")
                .disabled(model.selectedSlice == nil)

            Button("Delete") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!model.hasSelection)
        }

        CommandMenu("Slice") {
            ForEach(SlicerTool.allCases) { tool in
                Button(tool.label) {
                    model.activeTool = tool
                    if tool == .crop { model.prepareCropIfNeeded() }
                }
                .keyboardShortcut(KeyEquivalent(tool.label.lowercased().first ?? "s"), modifiers: [])
            }

            Divider()

            Button("Crop & Save…") { model.cropAndSave() }
                .disabled(!model.canCropAndSave)

            Button("Reset Crop") { model.resetCrop() }
                .disabled(model.cropRect == nil)

            Divider()

            Button("Suggest Guides") { model.suggestGuides() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!model.canSuggestGuides)

            Button("Auto Slice from Guides") { model.autoSlice() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(!model.canAutoSlice)

            Button("Apply Layout to All Images") { model.applyLayoutToAllImages() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(!model.hasMultipleImages)

            Menu("Templates") {
                ForEach(model.templates.all) { template in
                    Button("\(template.name) — \(template.columns) × \(template.rows)") {
                        model.apply(template)
                    }
                }
            }
            .disabled(!model.hasSource)

            Divider()

            Toggle("Snap to Guides and Slices", isOn: $model.isSnappingEnabled)
            Toggle("Snap to Centre Lines", isOn: $model.snapsToCentreLines)
            Toggle("Snap to Content Edges", isOn: $model.snapsToContentEdges)
            Toggle("Show Grid", isOn: $model.grid.isEnabled)

            Divider()

            Button("Edit Slice…") { model.inspectSelectedSlice() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.selectedSlice == nil)

            Button(model.selectedSliceIsLocked ? "Unlock Slice" : "Lock Slice") {
                model.toggleLockOnSelection()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(model.selectedSlice == nil)

            Button("Unlock All Slices") { model.unlockAllSlices() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!model.hasLockedSlices)

            Divider()

            Button("Clear Guides") { model.clearGuides() }
                .disabled(model.guides.isEmpty)
        }

        CommandGroup(after: .toolbar) {
            Button(model.isSidebarVisible ? "Hide Slices List" : "Show Slices List") {
                model.isSidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(!model.hasSource)
        }

        CommandGroup(after: .sidebar) {
            Button("Zoom In") { model.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!model.hasSource)

            Button("Zoom Out") { model.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!model.hasSource)

            Button("Fit to Window") { model.resetView() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!model.hasSource)
        }
    }
}
