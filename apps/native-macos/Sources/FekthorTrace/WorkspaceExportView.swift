import AppKit
import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

/// The workspace Export panel: manage the workfile's export profiles (name,
/// ordered action strings with live `ExportAction` validation, output
/// template) and run one over the workspace into a picked destination folder.
///
/// Edits are drafted locally and committed to the session's workfile with a
/// short debounce, so the `.fekthor` is rewritten once per pause, not per
/// keystroke. The run pipeline: read each SVG → apply the profile's actions
/// in order → write to the destination under the profile's naming template.
/// With "Compose containers" on, the membership matrix (icon × container) is
/// exported as well — compose first, then the profile's actions.
struct WorkspaceExportView: View {
    @ObservedObject var session: WorkspaceSession
    /// Gallery selection (entry id) backing the "Selected icon" scope.
    var selectedEntryID: String?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var runner = ExportRunController()
    @State private var profiles: [Workfile.ExportProfile] = []
    @State private var selected: Int? = nil
    @State private var commitTask: Task<Void, Never>? = nil

    @State private var scope: Scope = .workspace
    @State private var scopeCategory = ""
    @State private var composeContainers = false
    @State private var replaceExisting = false
    /// Off by default: containers and partials are composition ingredients,
    /// not products — a batch export only writes plain icons unless overridden.
    @State private var includeIngredients = false

    enum Scope: String, CaseIterable {
        case workspace = "Whole workspace"
        case category = "One category"
        case selection = "Selected icon"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Profiles").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            HSplitView {
                profileList
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: 260)
                profileDetail
                    .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            runBar
        }
        .frame(minWidth: 680, minHeight: 540)
        .onAppear {
            profiles = session.exportProfiles
            if !profiles.isEmpty { selected = 0 }
        }
        .onDisappear { commitNow() }
    }

    // MARK: - Profile list

    private var profileList: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(Array(profiles.enumerated()), id: \.offset) { index, profile in
                    HStack {
                        Text(profile.name.isEmpty ? "Untitled" : profile.name)
                        Spacer()
                        if !profileIsValid(profile) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                    .tag(index)
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack(spacing: 8) {
                Button {
                    addProfile(Workfile.ExportProfile(name: uniqueName("profile"), actions: []))
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    if let i = selected, profiles.indices.contains(i) {
                        var copy = profiles[i]
                        copy.name = uniqueName(copy.name)
                        addProfile(copy)
                    }
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .disabled(selected == nil)
                .help("Duplicate the selected profile")
                Button {
                    if let i = selected, profiles.indices.contains(i) {
                        profiles.remove(at: i)
                        selected = profiles.isEmpty ? nil : min(i, profiles.count - 1)
                        scheduleCommit()
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selected == nil)
                Spacer()
                presetsMenu
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    /// Presets: the open-icon library build (the exact five action strings
    /// its lib build reproduces) plus the two simple one-step profiles.
    private var presetsMenu: some View {
        Menu("Presets") {
            Button("Open-icon lib build") {
                addProfile(
                    Workfile.ExportProfile(
                        name: uniqueName("openicon-lib"),
                        actions: [
                            "recolor:stroke:#231f20=remove",
                            "recolor:stroke:#ed2024=var(--icon-stroke-color-secondary, var(--icon-stroke-color, currentColor))",
                            "recolor:fill:#ed2024=var(--icon-fill, rgba(0, 0, 0, 0))",
                            "restyle:opacity:.5=var(--icon-fill-opacity, 1)",
                            "stroke-width:4px=var(--icon-stroke-width-m, calc(var(--icon-stroke-width, 5) * 1))",
                        ],
                        output: "{name}.svg"))
            }
            Button("Outline strokes") {
                addProfile(
                    Workfile.ExportProfile(
                        name: uniqueName("outlined"), actions: ["outline-strokes"]))
            }
            Button("Flatten") {
                addProfile(
                    Workfile.ExportProfile(name: uniqueName("flat"), actions: ["flatten"]))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func addProfile(_ profile: Workfile.ExportProfile) {
        profiles.append(profile)
        selected = profiles.count - 1
        scheduleCommit()
    }

    private func uniqueName(_ base: String) -> String {
        let taken = Set(profiles.map(\.name))
        if !taken.contains(base) { return base }
        var counter = 2
        while taken.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    // MARK: - Profile detail

    @ViewBuilder
    private var profileDetail: some View {
        if let i = selected, profiles.indices.contains(i) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent("Name") {
                        TextField("Profile name", text: nameBinding(i))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                    }
                    LabeledContent("Output") {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("{name}.svg", text: outputBinding(i))
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                                .frame(maxWidth: 300)
                            Text("Template: {name} = icon, {profile} = profile. Default {name}.svg.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Divider()
                    Text("Actions (applied in order)").font(.subheadline.weight(.semibold))
                    actionRows(profileIndex: i)
                    Button {
                        var actions = profiles[i].actions ?? []
                        actions.append("")
                        profiles[i].actions = actions
                        scheduleCommit()
                    } label: {
                        Label("Add Action", systemImage: "plus")
                    }
                    Text(
                        "outline-strokes · flatten · strip-ids · resize:WxH · recolor:[fill:|stroke:]from=to · stroke-width:n|xF|n=value · restyle:prop:match=value"
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                .padding(14)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
                Text("Select a profile, add one, or start from a preset.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func actionRows(profileIndex i: Int) -> some View {
        let actions = profiles[i].actions ?? []
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(actions.enumerated()), id: \.offset) { row, action in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(row + 1).")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 20, alignment: .trailing)
                        TextField("action", text: actionBinding(profile: i, row: row))
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                        Button {
                            moveAction(profile: i, row: row, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(row == 0)
                        Button {
                            moveAction(profile: i, row: row, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(row == actions.count - 1)
                        Button {
                            var list = profiles[i].actions ?? []
                            list.remove(at: row)
                            profiles[i].actions = list
                            scheduleCommit()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                    }
                    .buttonStyle(.borderless)
                    if let problem = validationMessage(action) {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.leading, 26)
                    }
                }
            }
            if actions.isEmpty {
                Text("No actions — the profile copies icons unchanged (renamed by the template).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func moveAction(profile i: Int, row: Int, by delta: Int) {
        var list = profiles[i].actions ?? []
        let target = row + delta
        guard list.indices.contains(row), list.indices.contains(target) else { return }
        list.swapAt(row, target)
        profiles[i].actions = list
        scheduleCommit()
    }

    // MARK: - Validation

    /// Live per-row validation straight through the engine's parser, so the
    /// UI can never disagree with what a run would accept.
    private func validationMessage(_ raw: String) -> String? {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        do {
            _ = try ExportAction.parse(raw)
            return nil
        } catch let error as ExportActionError {
            return error.description
        } catch {
            return error.localizedDescription
        }
    }

    private func profileIsValid(_ profile: Workfile.ExportProfile) -> Bool {
        (try? ExportRunner.actions(of: profile)) != nil
    }

    // MARK: - Bindings / commit

    private func nameBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { profiles.indices.contains(i) ? profiles[i].name : "" },
            set: {
                guard profiles.indices.contains(i) else { return }
                profiles[i].name = $0
                scheduleCommit()
            })
    }

    private func outputBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { profiles.indices.contains(i) ? (profiles[i].output ?? "") : "" },
            set: {
                guard profiles.indices.contains(i) else { return }
                profiles[i].output = $0.isEmpty ? nil : $0
                scheduleCommit()
            })
    }

    private func actionBinding(profile i: Int, row: Int) -> Binding<String> {
        Binding(
            get: {
                guard profiles.indices.contains(i),
                    let actions = profiles[i].actions, actions.indices.contains(row)
                else { return "" }
                return actions[row]
            },
            set: {
                guard profiles.indices.contains(i),
                    var actions = profiles[i].actions, actions.indices.contains(row)
                else { return }
                actions[row] = $0
                profiles[i].actions = actions
                scheduleCommit()
            })
    }

    /// Debounced commit: the workfile is rewritten once per editing pause
    /// (and `updateSettings` skips the write entirely when nothing changed).
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            commitNow()
        }
    }

    private func commitNow() {
        commitTask?.cancel()
        commitTask = nil
        let drafted = profiles
        session.updateSettings { $0.exportProfiles = drafted }
    }

    // MARK: - Run bar

    private var runBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Run over", selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .fixedSize()
                if scope == .category {
                    Picker("", selection: $scopeCategory) {
                        Text("Uncategorized").tag("")
                        ForEach(session.workspace?.categories ?? [], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
                Toggle("Compose containers", isOn: $composeContainers)
                    .help(
                        "Also export the icon × container membership matrix (compose first, then the profile's actions)."
                    )
                Toggle("Replace existing files", isOn: $replaceExisting)
                    .help("Off: a file already at the destination is skipped and reported.")
                Spacer()
                Button("Export…") { pickDestinationAndRun() }
                    .disabled(!canRun)
            }
            HStack(spacing: 10) {
                Toggle("Include containers & partials", isOn: $includeIngredients)
                    .help(
                        "Containers and partials are composition ingredients and stay out of batch exports by default."
                    )
                if let note = exclusionNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if runner.running {
                HStack(spacing: 8) {
                    ProgressView(
                        value: Double(runner.done),
                        total: Double(max(runner.total, 1)))
                    Text("\(runner.done)/\(runner.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if !runner.summary.isEmpty {
                Text(runner.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !runner.errors.isEmpty {
                DisclosureGroup("\(runner.errors.count) problems") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(runner.errors.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.caption).foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 90)
                }
                .font(.caption)
            }
        }
        .padding(12)
    }

    private var canRun: Bool {
        guard !runner.running, let i = selected, profiles.indices.contains(i),
            profileIsValid(profiles[i])
        else { return false }
        if scope == .selection && selectedEntry == nil { return false }
        return !scopedEntries.isEmpty || (composeContainers && !session.containerSlots.isEmpty)
    }

    private var selectedEntry: IconEntry? {
        guard let selectedEntryID else { return nil }
        return session.workspace?.entries.first { $0.id == selectedEntryID }
    }

    /// The raw scope, before role filtering.
    private var scopedEntriesRaw: [IconEntry] {
        guard let ws = session.workspace else { return [] }
        switch scope {
        case .workspace:
            return ws.entries
        case .category:
            return ws.entries(in: scopeCategory)
        case .selection:
            return selectedEntry.map { [$0] } ?? []
        }
    }

    /// What the batch actually exports: plain icons only, unless the
    /// override includes the ingredients too.
    private var scopedEntries: [IconEntry] {
        guard !includeIngredients else { return scopedEntriesRaw }
        return scopedEntriesRaw.filter { session.settings.isExportedByDefault($0.name) }
    }

    /// "2 containers, 3 partials excluded — ingredients only", or nil when
    /// nothing in scope is excluded.
    private var exclusionNote: String? {
        guard !includeIngredients else { return nil }
        var containers = 0
        var partials = 0
        for entry in scopedEntriesRaw {
            switch session.settings.role(of: entry.name) {
            case .container: containers += 1
            case .partial: partials += 1
            case .icon: break
            }
        }
        guard containers + partials > 0 else { return nil }
        var parts: [String] = []
        if containers > 0 { parts.append("\(containers) container\(containers == 1 ? "" : "s")") }
        if partials > 0 { parts.append("\(partials) partial\(partials == 1 ? "" : "s")") }
        return parts.joined(separator: ", ") + " excluded — ingredients only."
    }

    private func pickDestinationAndRun() {
        guard let i = selected, profiles.indices.contains(i) else { return }
        commitNow()
        let profile = profiles[i]
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder the exported SVGs are written into."
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        runner.run(
            entries: scopedEntries,
            allEntries: session.workspace?.entries ?? [],
            profile: profile,
            slots: composeContainers ? session.containerSlots : [],
            memberships: composeContainers ? session.containerMemberships : [:],
            partialLinks: composeContainers ? session.partialLinks : [:],
            compose: composeContainers,
            namedStyles: session.settings.namedStyles ?? [],
            destination: destination,
            replaceExisting: replaceExisting
        ) { finished in
            session.status = finished
        }
    }
}

// MARK: - Export run controller

/// Runs one export batch off the main actor: read each scoped SVG, apply the
/// profile, write into the destination. Per-file failures are collected and
/// reported — one bad file never aborts the batch. Output order (and thus
/// error order) is deterministic: entries in workspace scan order, then the
/// sorted container matrix.
@MainActor
final class ExportRunController: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var summary = ""
    @Published private(set) var errors: [String] = []

    func run(
        entries: [IconEntry], allEntries: [IconEntry], profile: Workfile.ExportProfile,
        slots: [Workfile.ContainerSlot], memberships: [String: [String]],
        partialLinks: [String: [String]], compose: Bool,
        namedStyles: [NamedStyle] = [],
        destination: URL, replaceExisting: Bool, onFinished: @escaping (String) -> Void
    ) {
        guard !running else { return }
        running = true
        done = 0
        total = 0
        summary = ""
        errors = []

        Task.detached(priority: .userInitiated) {
            var problems: [String] = []
            let scoped = destination.startAccessingSecurityScopedResource()
            defer { if scoped { destination.stopAccessingSecurityScopedResource() } }

            // 1. Read the scoped documents (scan order = deterministic).
            var docs: [(name: String, doc: GraphicDocument)] = []
            for entry in entries {
                do {
                    let data = try Data(contentsOf: entry.url)
                    docs.append((entry.name, try SVGReader.read(data)))
                } catch {
                    problems.append("\(entry.fileName): could not read (\(error.localizedDescription))")
                }
            }

            // 2. Compose the container matrix, when asked: content documents
            //    are the scoped icons, container documents come from the
            //    whole workspace (a container need not be in scope).
            var composed: [(fileName: String, doc: GraphicDocument)] = []
            if compose {
                var containers: [String: (GraphicDocument, Workfile.ContainerSlot)] = [:]
                for slot in slots {
                    guard let entry = allEntries.first(where: { $0.name == slot.container })
                    else {
                        problems.append(
                            "container \(slot.container): no \(slot.container).svg in the workspace")
                        continue
                    }
                    do {
                        let data = try Data(contentsOf: entry.url)
                        containers[slot.container] = (try SVGReader.read(data), slot)
                    } catch {
                        problems.append(
                            "container \(slot.container): could not read (\(error.localizedDescription))")
                    }
                }
                // Linked partials merge into their containers before the
                // matrix composes; a partial whose file vanished is simply
                // skipped (matching the engine's contract).
                var partialsByContainer: [String: [String]] = [:]
                for (partial, containerNames) in partialLinks {
                    for name in containerNames {
                        partialsByContainer[name, default: []].append(partial)
                    }
                }
                var partialDocs: [String: GraphicDocument] = [:]
                for name in Set(partialLinks.keys).sorted() {
                    guard let entry = allEntries.first(where: { $0.name == name }) else {
                        continue
                    }
                    if let data = try? Data(contentsOf: entry.url),
                        let doc = try? SVGReader.read(data)
                    {
                        partialDocs[name] = doc
                    } else {
                        problems.append("partial \(name): could not read — merged without it")
                    }
                }
                let icons = Dictionary(docs.map { ($0.name, $0.doc) }) { first, _ in first }
                let scopedMemberships = memberships.filter { icons[$0.key] != nil }
                do {
                    composed = try Containers.matrixExports(
                        icons: icons, containers: containers, memberships: scopedMemberships,
                        partials: partialDocs, partialsByContainer: partialsByContainer)
                } catch Containers.ExportError.unknownContainers(let names) {
                    problems.append(
                        "memberships reference unknown containers: \(names.joined(separator: ", ")) — matrix skipped")
                } catch {
                    problems.append("container matrix failed: \(error.localizedDescription)")
                }
            }

            let plannedTotal = docs.count + composed.count
            await MainActor.run { self.total = plannedTotal }

            // 3. Apply + write. Plain icons first, then the matrix; composed
            //    documents go through the same profile actions ({name} is the
            //    composed "icon-container" stem).
            var written = 0
            var progress = 0
            func writeOut(_ fileName: String, _ doc: GraphicDocument) {
                // The name comes from a user-editable template ({name} /
                // {profile}); it must never escape the picked folder.
                let safeName: String
                do {
                    safeName = try ExportRunner.safeFileName(fileName)
                } catch {
                    problems.append("\(fileName): \(error) — skipped")
                    return
                }
                let target = destination.appendingPathComponent(safeName).standardizedFileURL
                guard target.path.hasPrefix(destination.standardizedFileURL.path + "/") else {
                    problems.append(
                        "\(fileName): resolves outside the destination folder — skipped")
                    return
                }
                do {
                    try FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    if !replaceExisting, FileManager.default.fileExists(atPath: target.path) {
                        problems.append("\(fileName): already exists — skipped (nothing overwritten)")
                        return
                    }
                    try SVGWriter.write(doc).write(to: target, atomically: true, encoding: .utf8)
                    written += 1
                } catch {
                    problems.append("\(fileName): could not write (\(error.localizedDescription))")
                }
            }
            func bump() async {
                progress += 1
                let p = progress
                await MainActor.run { self.done = p }
            }

            for (name, doc) in docs {
                do {
                    let result = try ExportRunner.apply(
                        profile: profile, to: doc, name: name, namedStyles: namedStyles)
                    writeOut(result.fileName, result.document)
                } catch {
                    problems.append("\(name): \(error)")
                }
                await bump()
            }
            for (fileName, doc) in composed {
                let stem = fileName.hasSuffix(".svg") ? String(fileName.dropLast(4)) : fileName
                do {
                    let result = try ExportRunner.apply(
                        profile: profile, to: doc, name: stem, namedStyles: namedStyles)
                    writeOut(result.fileName, result.document)
                } catch {
                    problems.append("\(stem): \(error)")
                }
                await bump()
            }

            let finalWritten = written
            let finalProblems = problems
            await MainActor.run {
                self.running = false
                self.errors = finalProblems
                let issue = finalProblems.isEmpty ? "" : " · \(finalProblems.count) problems"
                self.summary =
                    "Exported \(finalWritten) of \(plannedTotal) files to \(destination.lastPathComponent)\(issue)."
                onFinished(self.summary)
            }
        }
    }
}
