import AppKit
import FekthorKit
import SwiftUI

// The Styles palette: the workspace's named graphic styles (workfile
// `namedStyles`, engine `NamedStyles`) — live-preview rows that apply on
// click, capture from the selection, rename/retag, export-class opt-in,
// delete (keep or strip the binding class), and "Update from Selection"
// with workspace-wide propagation (read every SVG, rewrite ONLY changed
// documents, count-confirmed — the tokens retheme flow). The Classes editor
// lives at the bottom of the same palette: the selection's class tokens as
// chips (style-binding classes marked, user classes deletable) plus a
// validated add field.

// MARK: - Class token helpers (app-side)

/// Class attribute tokenization. Mirrors the engine's internal
/// `NamedStyles.classList`/`settingClassList` (not public — engine gap);
/// semantics are identical so bindings stay byte-compatible.
enum ClassTokens {
    /// The node's class attribute as a token list (empty when absent).
    static func list(_ attributes: NodeAttributes) -> [String] {
        guard let attr = attributes.extras.first(where: { $0.name == "class" }) else {
            return []
        }
        return attr.value.split(separator: " ").map(String.init)
    }

    /// Attributes with the class list replaced in place; an empty list
    /// removes the attribute entirely.
    static func setting(_ attributes: NodeAttributes, to classes: [String]) -> NodeAttributes {
        var out = attributes
        if classes.isEmpty {
            out.extras.removeAll { $0.name == "class" }
            return out
        }
        let value = classes.joined(separator: " ")
        if let i = out.extras.firstIndex(where: { $0.name == "class" }) {
            out.extras[i].value = value
        } else {
            out.extras.append(XMLAttr(name: "class", value: value))
        }
        return out
    }
}

/// Whole-tree class retagging (style rename / delete-with-strip): pure
/// walkers over shapes AND groups, document order, `changed` out-flag so
/// callers write only documents that actually changed.
enum ClassRetag {
    static func rename(
        _ nodes: [GraphicNode], old: String, new: String, changed: inout Bool
    ) -> [GraphicNode] {
        transform(nodes, changed: &changed) { classes in
            guard classes.contains(old) else { return nil }
            var seen: Set<String> = []
            return classes.map { $0 == old ? new : $0 }.filter { seen.insert($0).inserted }
        }
    }

    static func strip(
        _ nodes: [GraphicNode], token: String, changed: inout Bool
    ) -> [GraphicNode] {
        transform(nodes, changed: &changed) { classes in
            guard classes.contains(token) else { return nil }
            return classes.filter { $0 != token }
        }
    }

    /// Apply `edit` (nil = untouched) to every node's class list.
    private static func transform(
        _ nodes: [GraphicNode], changed: inout Bool, _ edit: ([String]) -> [String]?
    ) -> [GraphicNode] {
        nodes.map { node in
            switch node {
            case .raw:
                return node
            case .shape(var s):
                if let next = edit(ClassTokens.list(s.attributes)) {
                    s.attributes = ClassTokens.setting(s.attributes, to: next)
                    changed = true
                }
                return .shape(s)
            case .group(var g):
                if let next = edit(ClassTokens.list(g.attributes)) {
                    g.attributes = ClassTokens.setting(g.attributes, to: next)
                    changed = true
                }
                g.children = transform(g.children, changed: &changed, edit)
                return .group(g)
            }
        }
    }
}

// MARK: - Styles palette content

struct StylesPanelContent: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var workspace: WorkspaceSession
    @StateObject private var propagation = StyleWorkspaceController()

    // Name prompts (alert-hosted text fields).
    @State private var namingNew = false
    @State private var newName = ""
    @State private var renamingStyle: String? = nil
    @State private var renameText = ""
    @State private var renamePrompt = false
    @State private var deletingStyle: String? = nil
    @State private var deletePrompt = false
    /// Inline validation / result note under the styles list.
    @State private var note: String? = nil

    // Classes editor.
    @State private var newClass = ""
    @State private var classNote: String? = nil

    // File-local styles (FileMeta, no workspace needed).
    @State private var namingNewFileStyle = false
    @State private var newFileStyleName = ""
    @State private var renamingFileStyle: String? = nil
    @State private var renameFileText = ""
    @State private var renameFilePrompt = false

    private var styles: [NamedStyle] { workspace.settings.namedStyles ?? [] }
    private var styleNames: [String] { styles.map(\.name) }
    private var fileStyles: [NamedStyle] { session.fileStyles }
    /// Every style name in play — file-local AND workspace — so applying
    /// either layer swaps any other binding class cleanly, and names stay
    /// unique across both.
    private var allStyleNames: [String] { fileStyles.map(\.name) + styleNames }
    private var singleShapeSelected: Bool {
        session.selection.count == 1
            && session.selection.first.flatMap { session.document.firstShape(id: $0) } != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            fileStylesSection
            Divider()
            stylesSection
            Divider()
            classesSection
        }
        .background(confirmHost)
        .background(newStyleHost)
        .background(renameHost)
        .background(deleteHost)
        .background(newFileStyleHost)
        .background(renameFileStyleHost)
        .onChange(of: session.selection) { _, _ in classNote = nil }
    }

    // MARK: File-local styles (work with no workspace at all)

    /// Styles stored IN the open file (FileMeta): the per-file layer under
    /// the workspace's shared styles — labelled sections, file first.
    private var fileStylesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("This file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    newFileStyleName = ""
                    namingNewFileStyle = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!singleShapeSelected)
                .opacity(singleShapeSelected ? 1 : 0.4)
                .help("New file-local style from the selected shape (saved inside the SVG)")
            }
            if fileStyles.isEmpty {
                Text("No file styles yet — they save inside this SVG and need no workspace.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(fileStyles, id: \.name) { style in
                    fileStyleRow(style)
                }
            }
        }
    }

    private func fileStyleRow(_ style: NamedStyle) -> some View {
        Button {
            note = nil
            session.applyNamedStyle(style, roster: allStyleNames)
        } label: {
            HStack(spacing: 8) {
                NamedStyleSwatch(style: style)
                Text(style.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
            }
            .padding(4)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Apply “\(style.name)” to the selection")
        .contextMenu {
            Button("Apply to Selection") {
                note = nil
                session.applyNamedStyle(style, roster: allStyleNames)
            }
            Button("Update from Selection") { updateFileStyleFromSelection(style) }
                .disabled(!singleShapeSelected)
            Divider()
            Button("Rename…") {
                renamingFileStyle = style.name
                renameFileText = style.name
                renameFilePrompt = true
            }
            Divider()
            Button("Delete, Keep Classes") { deleteFileStyle(style.name, strip: false) }
            Button("Delete and Strip Classes", role: .destructive) {
                deleteFileStyle(style.name, strip: true)
            }
        }
    }

    private func createFileStyle() {
        guard let name = validatedStyleName(newFileStyleName, renamingFrom: nil) else { return }
        guard let captured = session.captureNamedStyle(named: name) else {
            note = "Select exactly one shape to capture a style."
            return
        }
        session.setFileStyles(fileStyles + [captured])
        session.applyNamedStyle(captured, roster: allStyleNames + [name])
        note = nil
    }

    /// File styles bind by class exactly like workspace styles, but their
    /// reach ends at the open document — propagation is a plain in-document
    /// rewrite, no workspace pass.
    private func updateFileStyleFromSelection(_ style: NamedStyle) {
        guard let captured = session.captureNamedStyle(named: style.name) else {
            note = "Select exactly one shape to update “\(style.name)” from."
            return
        }
        var updated = style
        updated.declarations = captured.declarations
        guard updated != style else {
            note = "“\(style.name)” already matches the selection."
            return
        }
        session.setFileStyles(
            fileStyles.map { $0.name == style.name ? updated : $0 })
        session.propagateNamedStyle(updated)
        note = nil
    }

    private func commitFileStyleRename() {
        guard let old = renamingFileStyle else { return }
        renamingFileStyle = nil
        guard let new = validatedStyleName(renameFileText, renamingFrom: old), new != old
        else { return }
        session.setFileStyles(
            fileStyles.map { style in
                var out = style
                if out.name == old { out.name = new }
                return out
            })
        session.retagClassInDocument(from: old, to: new)
        note = nil
    }

    private func deleteFileStyle(_ name: String, strip: Bool) {
        session.setFileStyles(fileStyles.filter { $0.name != name })
        if strip {
            session.stripClassInDocument(name)
        } else {
            note = "Deleted “\(name)” — bound nodes keep the class as a plain user class."
        }
    }

    private var newFileStyleHost: some View {
        Color.clear
            .alert("New File Style from Selection", isPresented: $namingNewFileStyle) {
                TextField("style-name", text: $newFileStyleName)
                Button("Create") { createFileStyle() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Captures the selected shape's paints into a style stored INSIDE this SVG — no workspace needed. The name doubles as the binding class: one token, no spaces."
                )
            }
    }

    private var renameFileStyleHost: some View {
        Color.clear
            .alert("Rename File Style", isPresented: $renameFilePrompt) {
                TextField("style-name", text: $renameFileText)
                Button("Rename") { commitFileStyleRename() }
                Button("Cancel", role: .cancel) { renamingFileStyle = nil }
            } message: {
                Text("Renames the style and retags its class on every bound node in this file.")
            }
    }

    // MARK: Styles list

    private var stylesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Workspace styles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if workspace.workspace != nil {
                    newStyleButton
                }
            }
            if workspace.workspace == nil {
                Text("Open a workspace — named styles are shared through its workfile.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if styles.isEmpty {
                Text("No styles yet — select a shape and press + to capture its paints as a style.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(styles, id: \.name) { style in
                    styleRow(style)
                }
                Text("Click a style to apply it to the selection")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if propagation.busy {
                ProgressView(
                    value: Double(propagation.done), total: Double(max(propagation.total, 1)))
            }
            if let text = note ?? propagation.note {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var newStyleButton: some View {
        Button {
            newName = ""
            namingNew = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!singleShapeSelected)
        .opacity(singleShapeSelected ? 1 : 0.4)
        .help("New style from the selected shape (select exactly one shape)")
    }

    private func styleRow(_ style: NamedStyle) -> some View {
        Button {
            apply(style)
        } label: {
            HStack(spacing: 8) {
                NamedStyleSwatch(style: style)
                Text(style.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if style.exportClass == true {
                    Text("class")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.14), in: Capsule())
                        .help("The binding class survives export")
                }
            }
            .padding(4)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Apply “\(style.name)” to the selection")
        .contextMenu {
            Button("Apply to Selection") { apply(style) }
            Button("Update from Selection") { updateFromSelection(style) }
                .disabled(!singleShapeSelected)
            Divider()
            Button("Rename…") {
                renamingStyle = style.name
                renameText = style.name
                renamePrompt = true
            }
            Toggle("Class Survives Export", isOn: exportClassBinding(style.name))
            Divider()
            Button("Delete…", role: .destructive) {
                deletingStyle = style.name
                deletePrompt = true
            }
        }
    }

    // MARK: Actions

    private func apply(_ style: NamedStyle) {
        note = nil
        session.applyNamedStyle(style, roster: allStyleNames)
    }

    /// "+": capture the selected shape's paints, add to the workfile, bind
    /// the shape (apply). Name is validated as a class token.
    private func createStyle() {
        guard let name = validatedStyleName(newName, renamingFrom: nil) else { return }
        guard let captured = session.captureNamedStyle(named: name) else {
            note = "Select exactly one shape to capture a style."
            return
        }
        workspace.updateSettings { workfile in
            var list = workfile.namedStyles ?? []
            list.append(captured)
            workfile.namedStyles = list
        }
        session.applyNamedStyle(captured, roster: allStyleNames + [name])
        note = nil
    }

    /// Overwrite the style's declarations from the selected shape, rewrite
    /// the open document's bound nodes (one undo step), then stage the
    /// workspace propagation (count-confirmed).
    private func updateFromSelection(_ style: NamedStyle) {
        guard let captured = session.captureNamedStyle(named: style.name) else {
            note = "Select exactly one shape to update “\(style.name)” from."
            return
        }
        var updated = style
        updated.declarations = captured.declarations
        guard updated != style else {
            note = "“\(style.name)” already matches the selection."
            return
        }
        workspace.updateSettings { workfile in
            guard var list = workfile.namedStyles,
                let i = list.firstIndex(where: { $0.name == style.name })
            else { return }
            list[i] = updated
            workfile.namedStyles = list
        }
        note = nil
        session.propagateNamedStyle(updated)
        stageWorkspacePass(.propagate(updated))
    }

    private func commitRename() {
        guard let old = renamingStyle else { return }
        renamingStyle = nil
        guard let new = validatedStyleName(renameText, renamingFrom: old), new != old else {
            return
        }
        workspace.updateSettings { workfile in
            guard var list = workfile.namedStyles,
                let i = list.firstIndex(where: { $0.name == old })
            else { return }
            list[i].name = new
            workfile.namedStyles = list
        }
        note = nil
        // The open document retags immediately (undo-labelled)…
        session.retagClassInDocument(from: old, to: new)
        // …the rest of the workspace through the count-confirmed pass.
        stageWorkspacePass(.rename(old: old, new: new))
    }

    private func deleteStyle(_ name: String, stripClasses: Bool) {
        workspace.updateSettings { workfile in
            var list = workfile.namedStyles ?? []
            list.removeAll { $0.name == name }
            workfile.namedStyles = list.isEmpty ? nil : list
        }
        note = nil
        if stripClasses {
            session.stripClassInDocument(name)
            stageWorkspacePass(.strip(name))
        } else {
            note = "Deleted “\(name)” — bound files keep the class as a plain user class."
        }
    }

    /// A usable style name: trimmed, non-empty, a single class token (no
    /// spaces), unique among the styles. nil + note when invalid.
    private func validatedStyleName(_ raw: String, renamingFrom old: String?) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            note = "Style names cannot be empty."
            return nil
        }
        guard !name.contains(where: \.isWhitespace) else {
            note = "Style names cannot contain spaces (the name is the SVG class)."
            return nil
        }
        guard name == old || !allStyleNames.contains(name) else {
            note = "A style named “\(name)” already exists (file and workspace styles share one namespace)."
            return nil
        }
        return name
    }

    private func exportClassBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { styles.first(where: { $0.name == name })?.exportClass == true },
            set: { on in
                workspace.updateSettings { workfile in
                    guard var list = workfile.namedStyles,
                        let i = list.firstIndex(where: { $0.name == name })
                    else { return }
                    list[i].exportClass = on ? true : nil
                    workfile.namedStyles = list
                }
            })
    }

    // MARK: Workspace passes (read → change → confirm → write changed only)

    private func stageWorkspacePass(_ pass: StyleWorkspaceController.Pass) {
        propagation.stage(
            pass, entries: workspace.workspace?.entries ?? [], excluding: session.fileURL)
    }

    private func commitPendingPass() {
        guard let pending = propagation.pending else { return }
        propagation.commit(pending) { written, problems in
            workspace.status =
                "\(pending.pass.verb): \(written) \(written == 1 ? "file" : "files") rewritten"
                + (problems.isEmpty ? "." : " · \(problems.count) problems.")
            if !problems.isEmpty {
                workspace.errorMessage = problems.prefix(5).joined(separator: "\n")
            }
            workspace.rescanNow()
        }
    }

    // MARK: Alert hosts (each on its own background, gallery pattern)

    private var confirmHost: some View {
        Color.clear
            .alert(
                "Rewrite workspace files?",
                isPresented: Binding(
                    get: { propagation.pending != nil },
                    set: { if !$0 { propagation.cancelPending() } })
            ) {
                Button(
                    "Rewrite \(propagation.pending?.writes.count ?? 0) Files",
                    role: .destructive
                ) {
                    commitPendingPass()
                }
                Button("Cancel", role: .cancel) { propagation.cancelPending() }
            } message: {
                Text(propagation.pending?.message ?? "")
            }
    }

    private var newStyleHost: some View {
        Color.clear
            .alert("New Style from Selection", isPresented: $namingNew) {
                TextField("style-name", text: $newName)
                Button("Create") { createStyle() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Captures the selected shape's paints. The name doubles as the SVG class binding nodes to the style — one token, no spaces."
                )
            }
    }

    private var renameHost: some View {
        Color.clear
            .alert("Rename Style", isPresented: $renamePrompt) {
                TextField("style-name", text: $renameText)
                Button("Rename") { commitRename() }
                Button("Cancel", role: .cancel) { renamingStyle = nil }
            } message: {
                Text(
                    "Renames the style and retags its class on every bound node — the open document immediately, the rest of the workspace after a confirmation."
                )
            }
    }

    private var deleteHost: some View {
        Color.clear
            .confirmationDialog(
                "Delete “\(deletingStyle ?? "")”?", isPresented: $deletePrompt
            ) {
                Button("Delete, Keep Classes in Files") {
                    if let name = deletingStyle { deleteStyle(name, stripClasses: false) }
                    deletingStyle = nil
                }
                Button("Delete and Strip Classes…", role: .destructive) {
                    if let name = deletingStyle { deleteStyle(name, stripClasses: true) }
                    deletingStyle = nil
                }
                Button("Cancel", role: .cancel) { deletingStyle = nil }
            } message: {
                Text(
                    "Values are inline, so nothing changes visually either way. Keeping the class leaves it as a plain user class; stripping removes it from every bound file (count-confirmed)."
                )
            }
    }

    // MARK: - Classes editor

    private var classesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Classes")
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.selection.isEmpty {
                Text("Select nodes to see and edit their classes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                let common = commonClasses
                if common.isEmpty {
                    Text(
                        session.selection.count > 1
                            ? "No classes shared by the whole selection."
                            : "No classes on this node."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(common, id: \.self) { token in
                        classChip(token)
                    }
                }
                classAddField
                if let classNote {
                    Text(classNote)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    /// Classes present on EVERY selected node (multi-selection shows the
    /// intersection; additions apply to all).
    private var commonClasses: [String] {
        var common: Set<String>? = nil
        for id in session.selection {
            guard let node = session.document.firstNode(id: id) else { continue }
            let tokens = Set(ClassTokens.list(node.nodeAttributes))
            common = common.map { $0.intersection(tokens) } ?? tokens
        }
        return (common ?? []).sorted()
    }

    @ViewBuilder
    private func classChip(_ token: String) -> some View {
        let boundStyle = (fileStyles + styles).first { $0.name == token }
        HStack(spacing: 6) {
            if boundStyle != nil {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(token)
                .font(.caption.monospaced())
                .lineLimit(1)
            Spacer()
            if let boundStyle {
                Text(boundStyle.exportClass == true ? "exports" : "internal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Button {
                    session.removeClassFromSelection(token)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 16)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Remove “\(token)” from the selection")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        .help(
            boundStyle == nil
                ? "User class — always survives export"
                : boundStyle?.exportClass == true
                    ? "Style binding — the class survives export"
                    : "Style binding — internal, flattened away on export")
    }

    private var classAddField: some View {
        TextField("add class…", text: $newClass)
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospaced())
            .onSubmit { commitNewClass() }
    }

    private func commitNewClass() {
        let token = newClass.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return }
        guard !token.contains(where: \.isWhitespace) else {
            classNote = "Class names cannot contain spaces."
            return
        }
        guard !allStyleNames.contains(token) else {
            classNote = "“\(token)” names a style — click the style above to apply (and bind) it."
            return
        }
        classNote = nil
        session.addClassToSelection(token)
        newClass = ""
    }
}

// MARK: - Live style preview swatch

/// A ~28pt live preview of a named style on a white well: the style's fill
/// paints a rounded rect, its stroke draws a short cornered line honouring
/// width, caps, joins and dash — enough to tell "solid 4pt rounded" from
/// "dashed 1pt" at a glance.
private struct NamedStyleSwatch: View {
    let style: NamedStyle

    var body: some View {
        Canvas { ctx, size in
            let resolved = resolvedStyle
            let opacity = resolved.opacity ?? 1
            var painted = false
            if let fill = resolved.fill, let c = fill.renderColor {
                var fillOpacity = 1.0
                if case .number(let fo, _)? = resolved.value(of: "fill-opacity") {
                    fillOpacity = fo
                }
                let rect = CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 12)
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: 3),
                    with: .color(color(c).opacity(opacity * fillOpacity)))
                painted = true
            }
            if let stroke = resolved.stroke, let c = stroke.renderColor {
                var path = Path()
                path.move(to: CGPoint(x: 6, y: size.height - 8))
                path.addLine(to: CGPoint(x: size.width * 0.4, y: 8))
                path.addLine(to: CGPoint(x: size.width - 6, y: size.height - 10))
                var strokeStyle = StrokeStyle(
                    lineWidth: min(max(resolved.strokeWidth ?? 1, 0.75), 8))
                if case .keyword(let cap)? = resolved.value(of: "stroke-linecap") {
                    strokeStyle.lineCap =
                        cap == "round" ? .round : cap == "square" ? .square : .butt
                }
                if case .keyword(let join)? = resolved.value(of: "stroke-linejoin") {
                    strokeStyle.lineJoin = join == "round" ? .round : .miter
                }
                if case .raw(let dash)? = resolved.value(of: "stroke-dasharray"), dash != "none" {
                    let parts = dash.split(whereSeparator: { $0 == "," || $0 == " " })
                        .compactMap { Double($0) }
                    if !parts.isEmpty { strokeStyle.dash = parts.map { CGFloat($0) } }
                }
                ctx.stroke(path, with: .color(color(c).opacity(opacity)), style: strokeStyle)
                painted = true
            }
            if !painted {
                // A style of nothing but keywords: neutral placeholder.
                var path = Path()
                path.move(to: CGPoint(x: 8, y: size.height - 8))
                path.addLine(to: CGPoint(x: size.width - 8, y: 8))
                ctx.stroke(path, with: .color(.gray.opacity(0.5)), lineWidth: 1)
            }
        }
        .frame(width: 44, height: 28)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.25)))
    }

    /// Declarations resolved through the same CSS parser the reader uses.
    private var resolvedStyle: Style {
        let css = style.declarations.map { "\($0.key): \($0.value);" }.joined(separator: " ")
        return SVGStyle.parse(css)
    }

    private func color(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> Color {
        Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
}

// MARK: - Workspace pass controller

/// Off-main workspace passes for the Styles palette, in two phases like the
/// tokens retheme: `stage` reads every workspace SVG (skipping the open
/// document — the editor already rewrote it in memory, undo-labelled) and
/// computes the changed documents; the view confirms with the file count;
/// `commit` writes ONLY those documents in place.
@MainActor
final class StyleWorkspaceController: ObservableObject {
    enum Pass: Sendable {
        case propagate(NamedStyle)
        case rename(old: String, new: String)
        case strip(String)

        var verb: String {
            switch self {
            case .propagate(let style): return "Style “\(style.name)” updated"
            case .rename(let old, let new): return "Style “\(old)” renamed to “\(new)”"
            case .strip(let name): return "Class “\(name)” stripped"
            }
        }
    }

    struct Pending {
        var pass: Pass
        var writes: [URL: GraphicDocument]
        var message: String
    }

    @Published private(set) var busy = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var pending: Pending? = nil
    /// One-line result note ("No other workspace files were affected.").
    @Published private(set) var note: String? = nil

    func cancelPending() {
        pending = nil
    }

    func stage(_ pass: Pass, entries: [IconEntry], excluding: URL?) {
        guard !busy else { return }
        busy = true
        done = 0
        total = entries.count
        note = nil
        pending = nil
        let excludedPath = excluding?.standardizedFileURL.path
        Task.detached(priority: .userInitiated) {
            let writes = await self.changedDocuments(
                pass, entries: entries, excludedPath: excludedPath)
            await MainActor.run { self.finishStage(pass, writes: writes) }
        }
    }

    private func finishStage(_ pass: Pass, writes: [URL: GraphicDocument]) {
        busy = false
        guard !writes.isEmpty else {
            note = "No other workspace files were affected."
            return
        }
        let count = writes.count
        pending = Pending(
            pass: pass, writes: writes,
            message:
                "\(pass.verb): \(count) SVG \(count == 1 ? "file" : "files") in the workspace folder will be rewritten. Only style-bound declarations and class markers change; the gallery rescans automatically."
        )
    }

    /// Write the staged documents in place; `finished(written, problems)`
    /// runs on the main actor.
    func commit(_ pending: Pending, finished: @escaping (Int, [String]) -> Void) {
        guard !busy else { return }
        busy = true
        self.pending = nil
        done = 0
        total = pending.writes.count
        Task.detached(priority: .userInitiated) {
            var written = 0
            var problems: [String] = []
            var progress = 0
            for (url, doc) in pending.writes.sorted(by: { $0.key.path < $1.key.path }) {
                do {
                    try SVGWriter.write(doc).write(to: url, atomically: true, encoding: .utf8)
                    written += 1
                } catch {
                    problems.append(
                        "\(url.lastPathComponent): could not write (\(error.localizedDescription))"
                    )
                }
                progress += 1
                let p = progress
                await MainActor.run { self.done = p }
            }
            let w = written
            let list = problems
            await MainActor.run {
                self.busy = false
                finished(w, list)
            }
        }
    }

    /// Read every entry (except the open document) and return ONLY the
    /// documents the pass changed — the engine's save contract.
    private nonisolated func changedDocuments(
        _ pass: Pass, entries: [IconEntry], excludedPath: String?
    ) async -> [URL: GraphicDocument] {
        var out: [URL: GraphicDocument] = [:]
        var progress = 0
        for entry in entries {
            defer {
                progress += 1
                if progress % 25 == 0 || progress == entries.count {
                    let p = progress
                    Task { @MainActor in self.done = p }
                }
            }
            if let excludedPath, entry.url.standardizedFileURL.path == excludedPath {
                continue
            }
            guard let data = try? Data(contentsOf: entry.url),
                let doc = try? SVGReader.read(data)
            else { continue }
            if let changed = Self.applying(pass, to: doc) {
                out[entry.url] = changed
            }
        }
        return out
    }

    /// The pass applied to one document; nil when nothing changed.
    private nonisolated static func applying(_ pass: Pass, to doc: GraphicDocument)
        -> GraphicDocument?
    {
        switch pass {
        case .propagate(let style):
            return NamedStyles.propagate(style, docs: ["doc": doc])["doc"]
        case .rename(let old, let new):
            var changed = false
            var out = doc
            out.nodes = ClassRetag.rename(doc.nodes, old: old, new: new, changed: &changed)
            return changed ? out : nil
        case .strip(let token):
            var changed = false
            var out = doc
            out.nodes = ClassRetag.strip(doc.nodes, token: token, changed: &changed)
            return changed ? out : nil
        }
    }
}
