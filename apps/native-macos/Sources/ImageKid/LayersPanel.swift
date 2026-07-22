import SwiftUI
import ImageKidKit
import UniformTypeIdentifiers

/// Lists annotation layers front-to-back, with selection, reordering,
/// duplication and deletion. Front-most layer sits at the top of the list.
struct LayersPanel: View {
    @ObservedObject var session: ImageSession
    @ObservedObject var appModel: AppModel
    @Binding var offset: CGSize
    @Binding var size: CGSize
    let onMinimize: () -> Void

    @State private var editingID: UUID?
    @State private var editingText: String = ""
    @State private var draggingID: UUID?
    @State private var dropTargetID: UUID?
    @FocusState private var nameFieldFocused: Bool

    /// Front-most first (last in the draw array renders on top).
    private var orderedLayers: [Annotation] { session.annotations.reversed() }

    private var ungroupedLayers: [ImageLayer] {
        session.imageLayers.reversed().filter { session.groupID(forLayer: $0.id) == nil }
    }

    private func members(of group: LayerGroup) -> [ImageLayer] {
        group.memberIDs.reversed().compactMap { id in session.imageLayers.first { $0.id == id } }
    }

    private var canGroupSelection: Bool {
        let ids = session.selectedLayerIDs.isEmpty ? Set([session.selectedLayerID].compactMap { $0 }) : session.selectedLayerIDs
        return ids.contains { session.groupID(forLayer: $0) == nil }
    }

    var body: some View {
        FloatingToolPanel(
            title: "Layers",
            systemImage: "square.3.layers.3d",
            offset: $offset,
            onMinimize: onMinimize,
            resizable: true,
            size: $size,
            contentPadding: 0
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        // Unified stack, top-to-bottom — image layers and shapes
                        // share a z order; grouped layers nest under a folder header.
                        ForEach(panelRows) { r in
                            switch r {
                            case .group(let group):
                                groupHeader(group)
                            case .groupedLayer(let layer):
                                imageLayerRow(layer).padding(.leading, 18)
                            case .item(let item):
                                stackRow(item)
                                    .modifier(ReorderDrag(
                                        id: item.id, draggingID: $draggingID, dropTargetID: $dropTargetID,
                                        onDrop: { src in session.reorderStack(moving: src, above: item.id) }
                                    ))
                            }
                        }
                        if !session.baseUnlocked {
                            backgroundRow
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .thinScrollbars()
                }
                .frame(maxHeight: .infinity)

                controlBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func stackRow(_ item: StackItem) -> some View {
        switch item {
        case .layer(let layer): imageLayerRow(layer)
        case .annotation(let annotation): row(annotation)
        }
    }

    /// A row in the panel: a group folder header, a layer nested in a group, or a
    /// top-level stack item.
    private enum PanelRow: Identifiable {
        case group(LayerGroup)
        case groupedLayer(ImageLayer)
        case item(StackItem)
        var id: UUID {
            switch self {
            case .group(let g): return g.id
            case .groupedLayer(let l): return l.id
            case .item(let i): return i.id
            }
        }
    }

    /// Build the display list top-to-bottom, nesting grouped layers under their
    /// folder header (placed where the group's top-most member sits in z).
    private var panelRows: [PanelRow] {
        var rows: [PanelRow] = []
        var emitted = Set<UUID>()
        for item in session.stackTopToBottom {
            if case .layer(let layer) = item, let gid = session.groupID(forLayer: layer.id) {
                guard !emitted.contains(gid) else { continue }
                emitted.insert(gid)
                if let group = session.layerGroups.first(where: { $0.id == gid }) {
                    rows.append(.group(group))
                    if !group.isCollapsed {
                        let members = group.memberIDs
                            .compactMap { id in session.imageLayers.first { $0.id == id } }
                            .sorted { $0.z > $1.z }
                        for m in members { rows.append(.groupedLayer(m)) }
                    }
                }
            } else {
                rows.append(.item(item))
            }
        }
        return rows
    }

    private func row(_ layer: Annotation) -> some View {
        let isSelected = session.selectedAnnotationID == layer.id
        return HStack(spacing: 10) {
            Image(systemName: icon(for: layer))
                .font(.system(size: 13, weight: .medium))
                .frame(width: 22)
                .opacity(layer.isVisible ? 1 : 0.4)
            nameLabel(id: layer.id, text: label(for: layer), isSelected: isSelected) {
                session.renameAnnotation(id: layer.id, to: $0)
            }
            Spacer()
            visibilityButton(isOn: layer.isVisible) {
                session.toggleAnnotationVisibility(id: layer.id)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? Color.accentColor.opacity(0.30) : Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            session.selectedAnnotationID = layer.id
            session.selectedLayerID = nil
            session.selectionRect = nil
            if appModel.activeTool == .view { appModel.activeTool = .select }
        }
        .contextMenu {
            Button("Rename") { startRename(layer.id, current: label(for: layer)) }
            Button("Duplicate") { session.duplicateAnnotation(id: layer.id) }
            Button(layer.isVisible ? "Hide" : "Show") { session.toggleAnnotationVisibility(id: layer.id) }
            Divider()
            Button("Delete", role: .destructive) { session.removeAnnotation(id: layer.id) }
        }
    }

    private func imageLayerRow(_ layer: ImageLayer) -> some View {
        let isSelected = session.selectedLayerID == layer.id || session.selectedLayerIDs.contains(layer.id)
        let editingMask = session.maskEditLayerID == layer.id
        return HStack(spacing: 8) {
            Image(nsImage: layer.image)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .opacity(layer.isVisible ? 1 : 0.35)
            if let mask = layer.mask {
                Image(nsImage: mask)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(editingMask ? Color.accentColor : .white.opacity(0.25), lineWidth: editingMask ? 2 : 1)
                    )
                    .opacity(layer.isMaskEnabled ? 1 : 0.4)
                    .onTapGesture { session.beginMaskEdit(layerID: layer.id) }
                    .help("Click to edit mask")
            }
            nameLabel(id: layer.id, text: layer.name, isSelected: isSelected) {
                session.renameImageLayer(id: layer.id, to: $0)
            }
            Spacer()
            if layer.hasMask {
                Button {
                    session.toggleLayerMask(id: layer.id)
                } label: {
                    Image(systemName: "theatermask.and.paintbrush")
                        .font(.system(size: 11))
                        .opacity(layer.isMaskEnabled ? 1 : 0.35)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))
                .help(layer.isMaskEnabled ? "Disable mask" : "Enable mask")
            } else if isSelected {
                Button {
                    session.addLayerMask(id: layer.id)
                } label: {
                    Image(systemName: "theatermask.and.paintbrush")
                        .font(.system(size: 11))
                        .opacity(0.5)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .help("Add mask")
            }
            visibilityButton(isOn: layer.isVisible) {
                session.toggleImageLayerVisibility(id: layer.id)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? Color.accentColor.opacity(0.30) : Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                if session.selectedLayerIDs.contains(layer.id) {
                    session.selectedLayerIDs.remove(layer.id)
                } else {
                    session.selectedLayerIDs.insert(layer.id)
                }
            } else {
                session.selectedLayerIDs = [layer.id]
            }
            session.selectedLayerID = layer.id
            session.selectedAnnotationID = nil
        }
        .contextMenu {
            Button("Rename") { startRename(layer.id, current: layer.name) }
            Button("Duplicate") { session.duplicateImageLayer(id: layer.id) }
            Button(layer.isVisible ? "Hide" : "Show") { session.toggleImageLayerVisibility(id: layer.id) }
            Divider()
            if layer.hasMask {
                Button("Edit Mask") { session.beginMaskEdit(layerID: layer.id) }
            } else {
                Button("Add Mask") { session.addLayerMask(id: layer.id) }
            }
            Button("Invert Mask") { session.invertLayerMask(id: layer.id) }
            if layer.hasMask {
                Button(layer.isMaskEnabled ? "Disable Mask" : "Enable Mask") {
                    session.toggleLayerMask(id: layer.id)
                }
                Button("Delete Mask") { session.removeLayerMask(id: layer.id) }
            }
            Button(layer.hasMask ? "Redo Background Mask" : "Remove Background (Mask)") {
                session.selectedLayerID = layer.id
                appModel.removeBackgroundFromSelectedLayer()
            }
            .disabled(appModel.isRemovingBackground)
            Divider()
            Button("Delete", role: .destructive) { session.removeImageLayer(id: layer.id) }
        }
    }

    private func startRename(_ id: UUID, current: String) {
        editingText = current
        editingID = id
        nameFieldFocused = true
    }

    /// The open image itself, shown as the locked bottom layer.
    private var backgroundRow: some View {
        HStack(spacing: 10) {
            Image(nsImage: session.workingSourceImage)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text("Background")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer()
            if session.backgroundRemovedImage != nil {
                Image(systemName: "theatermask.and.paintbrush")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Button {
                session.unlockBackground()
            } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Unlock — make the background a movable layer")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Unlock Background") { session.unlockBackground() }
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button(session.backgroundRemovedImage != nil ? "Restore Background" : "Remove Background") {
                appModel.removeBackground()
            }
            .disabled(!appModel.canRemoveBackground)
        }
    }

    private func groupHeader(_ group: LayerGroup) -> some View {
        HStack(spacing: 8) {
            Button {
                session.toggleGroupCollapsed(id: group.id)
            } label: {
                Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            Image(systemName: "folder")
                .font(.system(size: 12))
                .opacity(group.isVisible ? 1 : 0.4)
            nameLabel(id: group.id, text: group.name, isSelected: false) {
                session.renameGroup(id: group.id, to: $0)
            }
            Spacer()
            visibilityButton(isOn: group.isVisible) {
                session.toggleGroupVisibility(id: group.id)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Ungroup") { session.ungroup(id: group.id) }
        }
    }

    @ViewBuilder
    private func nameLabel(id: UUID, text: String, isSelected: Bool, commit: @escaping (String) -> Void) -> some View {
        if editingID == id {
            TextField("", text: $editingText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($nameFieldFocused)
                .onSubmit { commit(editingText); editingID = nil }
                .onExitCommand { editingID = nil }
        } else {
            Text(text)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    editingText = text
                    editingID = id
                    nameFieldFocused = true
                }
        }
    }

    private func visibilityButton(isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOn ? "eye" : "eye.slash")
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.7))
        .help(isOn ? "Hide" : "Show")
    }

    private var controlBar: some View {
        HStack(spacing: 6) {
            control("arrow.up", help: "Bring forward") {
                if let id = session.selectedLayerID ?? session.selectedAnnotationID {
                    session.moveStackItem(id, up: true)
                }
            }
            control("arrow.down", help: "Send backward") {
                if let id = session.selectedLayerID ?? session.selectedAnnotationID {
                    session.moveStackItem(id, up: false)
                }
            }
            Spacer()
            control("folder.badge.plus", help: "Group selected layers") {
                session.groupSelectedLayers()
            }
            .disabled(!canGroupSelection)
            control("plus.square.on.square", help: "Duplicate") {
                if let id = session.selectedAnnotationID { session.duplicateAnnotation(id: id) }
            }
            .disabled(session.selectedAnnotationID == nil)
            control("trash", help: "Delete") {
                if let id = session.selectedLayerID { session.removeImageLayer(id: id) }
                else if let id = session.selectedAnnotationID { session.removeAnnotation(id: id) }
            }
        }
        .disabled(session.selectedAnnotationID == nil && session.selectedLayerID == nil && session.selectedLayerIDs.isEmpty)
        .padding(.top, 2)
    }

    private func control(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 28)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func icon(for layer: Annotation) -> String {
        if layer.isText { return "textformat" }
        return layer.drawingMode?.symbolName ?? "square"
    }

    private func label(for layer: Annotation) -> String {
        if let custom = layer.customName, !custom.isEmpty { return custom }
        if layer.isText {
            let text = layer.textValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "Text" : text
        }
        return layer.drawingMode?.label ?? "Shape"
    }
}

/// Adds drag-to-reorder to a layer row: drag to pick up, drop onto another row
/// to move it there. Shows a highlight line at the drop target.
private struct ReorderDrag: ViewModifier {
    let id: UUID
    @Binding var draggingID: UUID?
    @Binding var dropTargetID: UUID?
    let onDrop: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .opacity(draggingID == id ? 0.35 : 1)
            .overlay(alignment: .top) {
                if dropTargetID == id, draggingID != id, draggingID != nil {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .offset(y: -3)
                }
            }
            .onDrag {
                draggingID = id
                return NSItemProvider(object: id.uuidString as NSString)
            }
            .onDrop(of: [UTType.plainText], delegate: ReorderDropDelegate(
                id: id, draggingID: $draggingID, dropTargetID: $dropTargetID, onDrop: onDrop
            ))
    }
}

private struct ReorderDropDelegate: DropDelegate {
    let id: UUID
    @Binding var draggingID: UUID?
    @Binding var dropTargetID: UUID?
    let onDrop: (UUID) -> Void

    func dropEntered(info: DropInfo) {
        if let dragging = draggingID, dragging != id { dropTargetID = id }
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == id { dropTargetID = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggingID = nil; dropTargetID = nil }
        guard let source = draggingID, source != id else { return false }
        onDrop(source)
        return true
    }
}
