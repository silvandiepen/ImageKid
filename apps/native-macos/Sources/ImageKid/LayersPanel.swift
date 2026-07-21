import SwiftUI
import ImageKidKit

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
            size: $size
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(session.layerGroups) { group in
                            groupHeader(group)
                            if !group.isCollapsed {
                                ForEach(members(of: group)) { layer in
                                    imageLayerRow(layer).padding(.leading, 18)
                                }
                            }
                        }
                        ForEach(ungroupedLayers) { layer in
                            imageLayerRow(layer)
                        }
                        ForEach(orderedLayers) { layer in
                            row(layer)
                        }
                        backgroundRow
                    }
                }
                .frame(maxHeight: .infinity)

                controlBar
            }
        }
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
    }

    private func imageLayerRow(_ layer: ImageLayer) -> some View {
        let isSelected = session.selectedLayerID == layer.id || session.selectedLayerIDs.contains(layer.id)
        return HStack(spacing: 10) {
            Image(nsImage: layer.image)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .opacity(layer.isVisible ? 1 : 0.35)
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
            Button(layer.hasMask ? "Redo Background Mask" : "Remove Background (Mask)") {
                session.selectedLayerID = layer.id
                appModel.removeBackgroundFromSelectedLayer()
            }
            .disabled(appModel.isRemovingBackground)
            if layer.hasMask {
                Button(layer.isMaskEnabled ? "Disable Mask" : "Enable Mask") {
                    session.toggleLayerMask(id: layer.id)
                }
                Button("Delete Mask") { session.removeLayerMask(id: layer.id) }
            }
        }
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
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                if let id = session.selectedLayerID { session.moveImageLayer(id: id, forward: true) }
                else if let id = session.selectedAnnotationID { session.moveAnnotation(id: id, forward: true) }
            }
            control("arrow.down", help: "Send backward") {
                if let id = session.selectedLayerID { session.moveImageLayer(id: id, forward: false) }
                else if let id = session.selectedAnnotationID { session.moveAnnotation(id: id, forward: false) }
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
