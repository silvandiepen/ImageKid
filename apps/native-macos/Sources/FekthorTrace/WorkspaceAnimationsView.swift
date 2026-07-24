import AppKit
import FekthorKit
import SwiftUI

/// The workspace Animations library (Workspace ▸ Animations…): the
/// workfile's reusable animation defs — add from built-in presets, edit
/// keyframes/timing in a focused editor with a live preview well, rename,
/// delete — plus the propagation pass that pushes an edited def into every
/// bound icon (read all, rewrite ONLY changed, count-confirmed; the tokens
/// retheme flow).
///
/// Deleting a def only removes the workspace master: bound icons keep
/// their resolved FileMeta copies and simply re-namespace icon-scoped on
/// their next save — nothing breaks.
struct WorkspaceAnimationsView: View {
    @ObservedObject var session: WorkspaceSession
    @Environment(\.dismiss) private var dismiss

    @StateObject private var propagator = AnimationWorkspaceController()
    @State private var defs: [AnimationDef] = []
    @State private var selectedDef: String? = nil
    @State private var commitTask: Task<Void, Never>? = nil
    /// Defs edited since the last propagation — the "Update icons" bar.
    @State private var dirtyDefs: Set<String> = []
    @State private var confirmPropagate = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Animations").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            HSplitView {
                defList
                    .frame(minWidth: 220, maxWidth: 300)
                detail
                    .frame(minWidth: 380, maxWidth: .infinity)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 680, minHeight: 540)
        .onAppear { defs = session.settings.animations ?? [] }
        .onDisappear { commitNow() }
        .background(confirmHost)
    }

    // MARK: - Def list

    private var defList: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedDef) {
                Section("Workspace") {
                    if defs.isEmpty {
                        Text("No animations yet — add a preset below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(defs, id: \.name) { def in
                        HStack {
                            Image(systemName: "sparkles")
                            Text(def.name)
                            Spacer()
                            Text("\(def.keyframes.count) keys")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(def.name)
                        .contextMenu {
                            Button("Duplicate") { duplicate(def) }
                            Button("Delete", role: .destructive) { delete(def) }
                        }
                    }
                }
                Section("Presets") {
                    ForEach(AnimationPresets.all, id: \.name) { preset in
                        HStack {
                            Image(systemName: "sparkle")
                            Text(preset.name).foregroundStyle(.secondary)
                            Spacer()
                            Button("Add") { add(preset) }
                                .controlSize(.mini)
                                .disabled(defs.contains { $0.name == preset.name })
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var detail: some View {
        Group {
            if let name = selectedDef, let index = defs.firstIndex(where: { $0.name == name }) {
                AnimationDefEditorView(
                    def: Binding(
                        get: { defs[index] },
                        set: { updated in
                            defs[index] = updated
                            dirtyDefs.insert(updated.name)
                            scheduleCommit()
                        }))
            } else {
                VStack {
                    Spacer()
                    Text("Select an animation to edit its keyframes and timing.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Status / propagation

    private var statusBar: some View {
        HStack(spacing: 10) {
            if propagator.running {
                ProgressView(value: Double(propagator.done), total: Double(max(propagator.total, 1)))
                    .frame(width: 160)
            }
            Text(propagator.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if !dirtyDefs.isEmpty {
                Button("Update Icons…") {
                    commitNow()
                    propagator.stage(
                        defs: defs.filter { dirtyDefs.contains($0.name) },
                        entries: session.workspace?.entries ?? [],
                        workfile: session.settings
                    ) {
                        confirmPropagate = true
                    }
                }
                .disabled(propagator.running)
                .help("Push the edited animations into every bound icon on disk")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var confirmHost: some View {
        Color.clear.confirmationDialog(
            "Rewrite \(propagator.stagedCount) icon file(s) with the updated animations?",
            isPresented: $confirmPropagate
        ) {
            Button("Rewrite \(propagator.stagedCount) Files") {
                propagator.commit(session: session) {
                    dirtyDefs.removeAll()
                }
            }
            Button("Cancel", role: .cancel) { propagator.discardStage() }
        } message: {
            Text("Only files bound to the edited animations change; every other icon is untouched.")
        }
    }

    // MARK: - Mutations

    private func add(_ preset: AnimationDef) {
        guard !defs.contains(where: { $0.name == preset.name }) else { return }
        defs.append(preset)
        selectedDef = preset.name
        scheduleCommit()
    }

    private func duplicate(_ def: AnimationDef) {
        var copy = def
        var n = 2
        while defs.contains(where: { $0.name == "\(def.name)-\(n)" }) { n += 1 }
        copy.name = "\(def.name)-\(n)"
        defs.append(copy)
        selectedDef = copy.name
        scheduleCommit()
    }

    private func delete(_ def: AnimationDef) {
        defs.removeAll { $0.name == def.name }
        dirtyDefs.remove(def.name)
        if selectedDef == def.name { selectedDef = nil }
        scheduleCommit()
    }

    /// Debounced workfile write (the tokens-view pattern).
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            commitNow()
        }
    }

    private func commitNow() {
        commitTask?.cancel()
        commitTask = nil
        let drafted = defs.map { $0.normalized() }
        session.updateSettings { $0.animations = drafted.isEmpty ? nil : drafted }
    }
}

// MARK: - Propagation controller

/// Stage → confirm-with-file-count → commit rewrite of bound icons after a
/// workspace def edit (the `StyleWorkspaceController` shape): read every
/// SVG off-main, run `AnimationEngine.propagate`, rewrite only changed
/// documents, then rescan.
@MainActor
final class AnimationWorkspaceController: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var summary = ""
    @Published private(set) var stagedCount = 0

    private var staged: [URL: String] = [:]

    func discardStage() {
        staged = [:]
        stagedCount = 0
    }

    /// Read all icons, compute the post-propagation documents, count the
    /// files that would change; `onStaged` fires with the count ready.
    func stage(
        defs: [AnimationDef], entries: [IconEntry], workfile: Workfile,
        onStaged: @escaping () -> Void
    ) {
        guard !running, !defs.isEmpty else { return }
        running = true
        done = 0
        total = entries.count
        summary = "Scanning \(entries.count) icons…"
        staged = [:]
        Task.detached(priority: .userInitiated) {
            var changed: [URL: String] = [:]
            var progress = 0
            for entry in entries {
                defer { progress += 1 }
                let p = progress
                await MainActor.run { self.done = p }
                guard let data = try? Data(contentsOf: entry.url),
                    var doc = try? SVGReader.read(data)
                else { continue }
                var touched = false
                for def in defs {
                    let rewritten = AnimationEngine.propagate(
                        def, workspace: workfile, docs: [entry.name: doc])
                    if let updated = rewritten[entry.name] {
                        doc = updated
                        touched = true
                    }
                }
                if touched {
                    changed[entry.url] = SVGWriter.write(doc)
                }
            }
            let finalChanged = changed
            await MainActor.run {
                self.running = false
                self.staged = finalChanged
                self.stagedCount = finalChanged.count
                self.summary =
                    finalChanged.isEmpty
                    ? "No icons are bound to the edited animations."
                    : "\(finalChanged.count) icon file(s) would update."
                if !finalChanged.isEmpty { onStaged() }
            }
        }
    }

    /// Write the staged rewrites and rescan the workspace.
    func commit(session: WorkspaceSession, onDone: @escaping () -> Void) {
        guard !running, !staged.isEmpty else { return }
        let files = staged
        running = true
        done = 0
        total = files.count
        Task.detached(priority: .userInitiated) {
            var written = 0
            var progress = 0
            for (url, svg) in files {
                defer { progress += 1 }
                let p = progress
                await MainActor.run { self.done = p }
                do {
                    try svg.write(to: url, atomically: true, encoding: .utf8)
                    written += 1
                } catch {
                    // Collected in the summary; one failure never aborts.
                }
            }
            let count = written
            await MainActor.run {
                self.running = false
                self.staged = [:]
                self.stagedCount = 0
                self.summary = "Updated \(count) icon file(s)."
                session.rescanNow()
                onDone()
            }
        }
    }
}

// MARK: - Def editor

/// Focused editor for ONE animation def: a normalized 0–100% keyframe
/// strip, per-keyframe declarations + easing, timing defaults, and a live
/// preview well driven by the same interpolator the canvas uses.
struct AnimationDefEditorView: View {
    @Binding var def: AnimationDef
    @State private var selectedOffset: Double? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(def.name).font(.title3.weight(.semibold))
                        Text(
                            def.normalizesPathLength == true
                                ? "draw-style (normalized path length)" : "keyframe animation"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AnimationPreviewWell(def: def)
                }
                keyframeStrip
                if let offset = selectedOffset,
                    let index = def.keyframes.firstIndex(where: { $0.offset == offset })
                {
                    keyframeEditor(index: index)
                }
                Divider()
                timingForm
            }
            .padding(16)
        }
    }

    // MARK: Keyframe strip

    private var keyframeStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Keyframes").font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    addKeyframe()
                } label: {
                    Label("Add at 50%", systemImage: "plus")
                }
                .controlSize(.small)
            }
            GeometryReader { geo in
                let width = geo.size.width - 16
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)
                        .padding(.horizontal, 8)
                    ForEach(def.keyframes.map(\.offset), id: \.self) { offset in
                        Diamond()
                            .fill(
                                selectedOffset == offset ? Color.accentColor : Color.secondary)
                            .frame(width: 11, height: 11)
                            .offset(x: 8 + CGFloat(offset / 100) * width - 5.5)
                            .onTapGesture { selectedOffset = offset }
                    }
                }
            }
            .frame(height: 24)
            HStack {
                Text("0%").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("100%").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func addKeyframe() {
        var offset = 50.0
        while def.keyframes.contains(where: { $0.offset == offset }), offset < 100 {
            offset += 5
        }
        let previous = def.keyframes.last { $0.offset < offset } ?? def.keyframes.first
        var next = def
        next.keyframes.append(
            AnimationKeyframe(offset: offset, declarations: previous?.declarations ?? [:]))
        def = next.normalized()
        selectedOffset = offset
    }

    // MARK: Keyframe editor

    private func keyframeEditor(index: Int) -> some View {
        let frame = def.keyframes[index]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: "Keyframe at %.0f%%", frame.offset))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Stepper(
                    value: Binding(
                        get: { frame.offset },
                        set: { newOffset in
                            let clamped = min(100, max(0, newOffset))
                            var next = def
                            next.keyframes[index].offset = clamped
                            def = next.normalized()
                            selectedOffset = clamped
                        }), in: 0...100, step: 1
                ) {
                    Text(String(format: "%.0f%%", frame.offset)).monospacedDigit()
                }
                .controlSize(.small)
                Button(role: .destructive) {
                    var next = def
                    next.keyframes.remove(at: index)
                    def = next
                    selectedOffset = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(def.keyframes.count <= 1)
            }
            ForEach(frame.declarations.keys.sorted(), id: \.self) { property in
                HStack(spacing: 6) {
                    Text(property)
                        .font(.caption)
                        .frame(width: 120, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField(
                        "value",
                        text: Binding(
                            get: { frame.declarations[property] ?? "" },
                            set: { text in
                                guard AnimationLint.isSafeValue(text) else { return }
                                def.keyframes[index].declarations[property] = text
                            }))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    Button {
                        def.keyframes[index].declarations.removeValue(forKey: property)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Menu {
                ForEach(
                    AnimationLint.animatableProperties
                        .subtracting(frame.declarations.keys).sorted(),
                    id: \.self
                ) { property in
                    Button(property) {
                        def.keyframes[index].declarations[property] = ""
                    }
                }
            } label: {
                Label("Add Property", systemImage: "plus")
            }
            .controlSize(.small)
            .fixedSize()
            easingRow(index: index, frame: frame)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }

    private func easingRow(index: Int, frame: AnimationKeyframe) -> some View {
        let easing = Binding(
            get: { frame.easing ?? "" },
            set: { def.keyframes[index].easing = $0.isEmpty ? nil : $0 })
        return HStack(alignment: .top, spacing: 6) {
            Text("easing out")
                .font(.caption)
                .frame(width: 120, alignment: .trailing)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: Binding(
                    get: {
                        easing.wrappedValue.hasPrefix("cubic-bezier(")
                            ? "custom" : easing.wrappedValue
                    },
                    set: { picked in
                        easing.wrappedValue =
                            picked == "custom" ? "cubic-bezier(.25, .1, .25, 1)" : picked
                    })
                ) {
                    Text("Inherit").tag("")
                    Text("linear").tag("linear")
                    Text("ease").tag("ease")
                    Text("ease-in").tag("ease-in")
                    Text("ease-out").tag("ease-out")
                    Text("ease-in-out").tag("ease-in-out")
                    Text("steps(2)").tag("steps(2, end)")
                    Text("custom curve").tag("custom")
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                if easing.wrappedValue.hasPrefix("cubic-bezier(") {
                    BezierCurveEditor(easing: easing)
                }
            }
        }
    }

    // MARK: Timing form

    private var timingForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timing defaults").font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Duration").gridColumnAlignment(.trailing)
                    TextField(
                        "0.8", value: timingBinding(\.duration), format: .number)
                        .frame(width: 70)
                    Text("seconds").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Delay")
                    TextField("0", value: timingBinding(\.delay), format: .number)
                        .frame(width: 70)
                    Text("seconds").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Iterations")
                    TextField("infinite", text: timingText(\.iterationCount))
                        .frame(width: 70)
                    Text("count or “infinite”").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Direction")
                    Picker("", selection: timingText(\.direction, empty: "normal")) {
                        Text("normal").tag("normal")
                        Text("reverse").tag("reverse")
                        Text("alternate").tag("alternate")
                        Text("alternate-reverse").tag("alternate-reverse")
                    }
                    .labelsHidden()
                    .fixedSize()
                    Text("").gridCellUnsizedAxes(.horizontal)
                }
                GridRow {
                    Text("Fill mode")
                    Picker("", selection: timingText(\.fillMode, empty: "none")) {
                        Text("none").tag("none")
                        Text("forwards").tag("forwards")
                        Text("backwards").tag("backwards")
                        Text("both").tag("both")
                    }
                    .labelsHidden()
                    .fixedSize()
                    Text("").gridCellUnsizedAxes(.horizontal)
                }
                GridRow {
                    Text("Origin")
                    TextField("center", text: timingText(\.transformOrigin))
                        .frame(width: 110)
                    Text("transform-origin").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
        }
    }

    private func timingBinding(_ keyPath: WritableKeyPath<AnimationTiming, Double?>)
        -> Binding<Double?>
    {
        Binding(
            get: { def.timing?[keyPath: keyPath] },
            set: { value in
                var timing = def.timing ?? AnimationTiming()
                timing[keyPath: keyPath] = value
                def.timing = timing
            })
    }

    private func timingText(
        _ keyPath: WritableKeyPath<AnimationTiming, String?>, empty: String = ""
    ) -> Binding<String> {
        Binding(
            get: { def.timing?[keyPath: keyPath] ?? empty },
            set: { value in
                var timing = def.timing ?? AnimationTiming()
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                timing[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
                def.timing = timing
            })
    }
}

// MARK: - Preview well

/// A small live preview of one def: a sample glyph (rounded rect + stroke
/// line) animated by the SAME interpolator the canvas uses, on a repeating
/// clock.
struct AnimationPreviewWell: View {
    let def: AnimationDef

    private let size: CGFloat = 84

    var body: some View {
        TimelineView(.animation) { tl in
            let cycle = max(
                (def.timing?.duration ?? 0.8) + (def.timing?.delay ?? 0), 0.4)
            let time = tl.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycle * 1.25)
            Canvas { ctx, canvasSize in
                let binding = AnimationBinding(
                    animation: def.name, target: "well", trigger: "continuous")
                let bounds = ViewBox(minX: 4, minY: 4, width: 16, height: 16)
                let overrides = AnimationInterpolator.resolve(
                    defs: [def], bindings: [binding], settings: AnimationSettings(),
                    time: time, state: AnimationPreviewState(forcePlay: true)
                ) { _ in
                    AnimationTargetContext(
                        bounds: bounds, baseOpacity: 1, baseStroke: .color(r: 1, g: 1, b: 1),
                        baseStrokeWidth: 2, pathLength: 64)
                }
                let scale = canvasSize.width / 24
                var transform = CGAffineTransform(scaleX: scale, y: scale)
                if let m = overrides["well"]?.transform {
                    transform = CGAffineTransform(
                        a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5]
                    ).concatenating(transform)
                }
                let o = overrides["well"]
                guard o?.hidden != true else { return }
                var glyph = Path(
                    roundedRect: CGRect(x: 4, y: 4, width: 16, height: 16), cornerRadius: 3)
                glyph = glyph.applying(transform)
                var stroke = StrokeStyle(lineWidth: (o?.strokeWidth ?? 2) * scale)
                if let dash = o?.strokeDasharray {
                    stroke.dash = [dash * scale, dash * scale]
                    stroke.dashPhase = (o?.strokeDashoffset ?? 0) * scale
                }
                let opacity = o?.opacity ?? 1
                let color: Color
                if case .color(let r, let g, let b)? = o?.stroke {
                    color = Color(
                        red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
                } else {
                    color = Color.primary
                }
                ctx.stroke(glyph, with: .color(color.opacity(opacity)), style: stroke)
                if case .color(let r, let g, let b)? = o?.fill {
                    ctx.fill(
                        glyph,
                        with: .color(
                            Color(
                                red: Double(r) / 255, green: Double(g) / 255,
                                blue: Double(b) / 255
                            ).opacity(opacity)))
                }
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        }
    }
}
