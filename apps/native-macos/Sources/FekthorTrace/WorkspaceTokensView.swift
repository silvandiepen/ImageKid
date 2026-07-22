import AppKit
import FekthorKit
import SwiftUI

/// The workspace Styles panel: the workfile's colour tokens (name + colour
/// well + hex, add/remove), a workspace-wide scan (bindings per token and
/// the unbound-colour census, off-main with progress), and retheme — change
/// a token's colour, preview how many files would change, then rewrite ONLY
/// the changed documents in place via `StyleTokens.apply` after an explicit
/// confirmation stating the file count.
struct WorkspaceTokensView: View {
    @ObservedObject var session: WorkspaceSession
    @Environment(\.dismiss) private var dismiss

    @StateObject private var scanner = TokenScanController()
    @State private var tokens: [Workfile.StyleToken] = []
    @State private var commitTask: Task<Void, Never>? = nil

    // Retheme state: token name → drafted new value (hex).
    @State private var rethemeName: String? = nil
    @State private var rethemeValue = ""
    @State private var confirmApply = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Style Tokens").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tokenSection
                    Divider()
                    scanSection
                    Divider()
                    rethemeSection
                }
                .padding(14)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear { tokens = session.styleTokens }
        .onDisappear { commitNow() }
        .background(confirmHost)
    }

    // MARK: - Token list

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tokens").font(.subheadline.weight(.semibold))
            if tokens.isEmpty {
                Text("No tokens yet — add one, or scan and create tokens from the census below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                HStack(spacing: 8) {
                    TextField("name", text: tokenNameBinding(index))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    ColorPicker("", selection: tokenColorBinding(index), supportsOpacity: false)
                        .labelsHidden()
                    TextField("#rrggbb", text: tokenValueBinding(index))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(width: 110)
                    if StyleTokens.normalizeColor(token.value) == nil {
                        Text("not a colour")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let count = scanner.bindingCounts[token.name] {
                        Text("\(count) bindings")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        rethemeName = token.name
                        rethemeValue = token.value
                        scanner.clearPreview()
                    } label: {
                        Text("Retheme…")
                    }
                    .disabled(StyleTokens.normalizeColor(token.value) == nil)
                    Button {
                        tokens.remove(at: index)
                        scheduleCommit()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                tokens.append(Workfile.StyleToken(name: uniqueTokenName("token"), value: "#000000"))
                scheduleCommit()
            } label: {
                Label("Add Token", systemImage: "plus")
            }
        }
    }

    // MARK: - Scan

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Workspace scan").font(.subheadline.weight(.semibold))
                Button("Scan") {
                    commitNow()
                    scanner.scan(entries: session.workspace?.entries ?? [], tokens: tokens)
                }
                .disabled(scanner.busy)
                if scanner.busy {
                    ProgressView(
                        value: Double(scanner.done), total: Double(max(scanner.total, 1))
                    )
                    .frame(width: 140)
                    Text("\(scanner.done)/\(scanner.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !scanner.summary.isEmpty {
                Text(scanner.summary).font(.caption).foregroundStyle(.secondary)
            }
            if !scanner.unbound.isEmpty {
                Text("Colours matching no token").font(.caption.weight(.semibold))
                ForEach(Array(scanner.unbound.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(of: item.rgb))
                            .frame(width: 16, height: 16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3).strokeBorder(.quaternary))
                        Text(item.rgb.hexText).font(.body.monospaced())
                        Text("in \(item.fileCount) \(item.fileCount == 1 ? "file" : "files")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button("Create token") {
                            tokens.append(
                                Workfile.StyleToken(
                                    name: uniqueTokenName("color"), value: item.rgb.hexText))
                            scheduleCommit()
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Retheme

    @ViewBuilder
    private var rethemeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Retheme").font(.subheadline.weight(.semibold))
            if let name = rethemeName, let token = tokens.first(where: { $0.name == name }) {
                HStack(spacing: 8) {
                    Text(name).font(.body.weight(.medium))
                    swatch(token.value)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    ColorPicker("", selection: rethemeColorBinding, supportsOpacity: false)
                        .labelsHidden()
                    TextField("#rrggbb", text: $rethemeValue)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(width: 110)
                        .onChange(of: rethemeValue) { _, _ in scanner.clearPreview() }
                    Button("Preview") {
                        commitNow()
                        scanner.preview(
                            entries: session.workspace?.entries ?? [], tokens: tokens,
                            name: name, newValue: rethemeValue)
                    }
                    .disabled(!rethemeReady || scanner.busy)
                    if let count = scanner.previewCount {
                        Text("\(count) \(count == 1 ? "file" : "files") would change")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button("Apply…") { confirmApply = true }
                            .disabled(count == 0 || scanner.busy)
                    }
                }
                Text(
                    "Apply rewrites only the SVG files whose paints carry this token's colour — everything else round-trips untouched."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            } else {
                Text("Pick “Retheme…” on a token above to recolour the workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rethemeReady: Bool {
        guard let name = rethemeName,
            let token = tokens.first(where: { $0.name == name }),
            let old = StyleTokens.normalizeColor(token.value),
            let new = StyleTokens.normalizeColor(rethemeValue)
        else { return false }
        return old != new
    }

    private var statusBar: some View {
        HStack {
            Text(session.status).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// The confirm-before-touching-workspace-files alert, hosted off the main
    /// body (gallery pattern).
    private var confirmHost: some View {
        Color.clear
            .alert("Rewrite workspace files?", isPresented: $confirmApply) {
                Button("Rewrite \(scanner.previewCount ?? 0) files", role: .destructive) {
                    applyRetheme()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Retheming “\(rethemeName ?? "")” to \(rethemeValue) rewrites \(scanner.previewCount ?? 0) SVG \((scanner.previewCount ?? 0) == 1 ? "file" : "files") in the workspace folder. Only bound colour declarations change; the gallery rescans automatically."
                )
            }
    }

    private func applyRetheme() {
        guard let name = rethemeName else { return }
        let newValue = rethemeValue
        scanner.applyRetheme(
            entries: session.workspace?.entries ?? [], tokens: tokens,
            name: name, newValue: newValue
        ) { written, problems in
            // The token now MEANS the new colour: update the workfile too.
            if let i = tokens.firstIndex(where: { $0.name == name }) {
                tokens[i].value = newValue
                commitNow()
            }
            session.status =
                "Retheme: \(written) \(written == 1 ? "file" : "files") rewritten"
                + (problems.isEmpty ? "." : " · \(problems.count) problems.")
            if !problems.isEmpty {
                session.errorMessage = problems.prefix(5).joined(separator: "\n")
            }
            session.rescanNow()
        }
    }

    // MARK: - Bindings / commit

    private func tokenNameBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { tokens.indices.contains(i) ? tokens[i].name : "" },
            set: {
                guard tokens.indices.contains(i) else { return }
                tokens[i].name = $0
                scheduleCommit()
            })
    }

    private func tokenValueBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { tokens.indices.contains(i) ? tokens[i].value : "" },
            set: {
                guard tokens.indices.contains(i) else { return }
                tokens[i].value = $0
                scheduleCommit()
            })
    }

    private func tokenColorBinding(_ i: Int) -> Binding<Color> {
        Binding(
            get: {
                guard tokens.indices.contains(i),
                    let rgb = StyleTokens.normalizeColor(tokens[i].value)
                else { return .black }
                return color(of: rgb)
            },
            set: {
                guard tokens.indices.contains(i) else { return }
                tokens[i].value = hex(of: $0)
                scheduleCommit()
            })
    }

    private var rethemeColorBinding: Binding<Color> {
        Binding(
            get: {
                guard let rgb = StyleTokens.normalizeColor(rethemeValue) else { return .black }
                return color(of: rgb)
            },
            set: {
                rethemeValue = hex(of: $0)
                scanner.clearPreview()
            })
    }

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
        let drafted = tokens
        session.updateSettings { $0.styleTokens = drafted }
    }

    private func uniqueTokenName(_ base: String) -> String {
        let taken = Set(tokens.map(\.name))
        if !taken.contains(base) { return base }
        var counter = 2
        while taken.contains("\(base)-\(counter)") { counter += 1 }
        return "\(base)-\(counter)"
    }

    // MARK: - Colour helpers

    private func color(of rgb: StyleTokens.RGB) -> Color {
        Color(
            red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    private func hex(of color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let r = UInt8(round(ns.redComponent * 255))
        let g = UInt8(round(ns.greenComponent * 255))
        let b = UInt8(round(ns.blueComponent * 255))
        return StyleTokens.RGB(r: r, g: g, b: b).hexText
    }

    private func swatch(_ value: String) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(StyleTokens.normalizeColor(value).map(color(of:)) ?? .clear)
            .frame(width: 16, height: 16)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.quaternary))
    }
}

// MARK: - Scan / retheme controller

/// Off-main workspace passes for the Styles panel: the binding/unbound scan,
/// the retheme preview (count of documents that would change), and the
/// retheme apply (rewrites ONLY changed documents, in place). Progress is
/// published per file so ~900-file workspaces show movement.
@MainActor
final class TokenScanController: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var summary = ""
    /// Token name → total bound declarations across the workspace.
    @Published private(set) var bindingCounts: [String: Int] = [:]
    /// Unbound colour census, ordered by file count (ties by hex).
    @Published private(set) var unbound: [(rgb: StyleTokens.RGB, fileCount: Int)] = []
    @Published private(set) var previewCount: Int? = nil

    func clearPreview() {
        previewCount = nil
    }

    // MARK: Scan

    struct ScanResult: Sendable {
        var counts: [String: Int] = [:]
        var unboundFiles: [StyleTokens.RGB: Int] = [:]
        var unreadable = 0
    }

    func scan(entries: [IconEntry], tokens: [Workfile.StyleToken]) {
        guard !busy else { return }
        begin(total: entries.count)
        Task.detached(priority: .userInitiated) {
            let result = await self.scanPass(entries: entries, tokens: tokens)
            await MainActor.run { self.finishScan(result, fileCount: entries.count) }
        }
    }

    private nonisolated func scanPass(
        entries: [IconEntry], tokens: [Workfile.StyleToken]
    ) async -> ScanResult {
        var result = ScanResult()
        var progress = 0
        for entry in entries {
            if let doc = Self.read(entry) {
                for binding in StyleTokens.bindings(in: doc, tokens: tokens) {
                    result.counts[binding.token, default: 0] += 1
                }
                for rgb in StyleTokens.unboundColors(in: doc, tokens: tokens) {
                    result.unboundFiles[rgb, default: 0] += 1
                }
            } else {
                result.unreadable += 1
            }
            progress += 1
            if progress % 25 == 0 || progress == entries.count {
                let p = progress
                await MainActor.run { self.done = p }
            }
        }
        return result
    }

    private func finishScan(_ result: ScanResult, fileCount: Int) {
        busy = false
        bindingCounts = result.counts
        unbound = result.unboundFiles
            .map { (rgb: $0.key, fileCount: $0.value) }
            .sorted {
                $0.fileCount == $1.fileCount
                    ? $0.rgb.hexText < $1.rgb.hexText : $0.fileCount > $1.fileCount
            }
        let bound = result.counts.values.reduce(0, +)
        summary =
            "Scanned \(fileCount) files: \(bound) token bindings, "
            + "\(unbound.count) unbound colours"
            + (result.unreadable > 0 ? ", \(result.unreadable) unreadable." : ".")
    }

    // MARK: Retheme

    func preview(
        entries: [IconEntry], tokens: [Workfile.StyleToken], name: String, newValue: String
    ) {
        guard !busy else { return }
        begin(total: entries.count)
        Task.detached(priority: .userInitiated) {
            let changed = await self.changedDocuments(
                entries: entries, tokens: tokens, name: name, newValue: newValue)
            await MainActor.run {
                self.busy = false
                self.previewCount = changed.count
            }
        }
    }

    /// Rewrites the changed documents in place. `finished(written, problems)`
    /// runs on the main actor.
    func applyRetheme(
        entries: [IconEntry], tokens: [Workfile.StyleToken], name: String, newValue: String,
        finished: @escaping (Int, [String]) -> Void
    ) {
        guard !busy else { return }
        begin(total: entries.count)
        Task.detached(priority: .userInitiated) {
            let changed = await self.changedDocuments(
                entries: entries, tokens: tokens, name: name, newValue: newValue)
            var written = 0
            var problems: [String] = []
            for (url, doc) in changed.sorted(by: { $0.key.path < $1.key.path }) {
                do {
                    try SVGWriter.write(doc).write(to: url, atomically: true, encoding: .utf8)
                    written += 1
                } catch {
                    problems.append(
                        "\(url.lastPathComponent): could not write (\(error.localizedDescription))")
                }
            }
            let w = written
            let p = problems
            await MainActor.run {
                self.busy = false
                self.previewCount = nil
                finished(w, p)
            }
        }
    }

    /// Reads every entry and returns ONLY the documents `StyleTokens.apply`
    /// changed (the engine's save contract), keyed by file URL.
    private nonisolated func changedDocuments(
        entries: [IconEntry], tokens: [Workfile.StyleToken], name: String, newValue: String
    ) async -> [URL: GraphicDocument] {
        var out: [URL: GraphicDocument] = [:]
        var progress = 0
        for entry in entries {
            if let doc = Self.read(entry),
                let changed = StyleTokens.apply(
                    tokens: tokens, changing: name, to: newValue, doc: doc)
            {
                out[entry.url] = changed
            }
            progress += 1
            if progress % 25 == 0 || progress == entries.count {
                let p = progress
                await MainActor.run { self.done = p }
            }
        }
        return out
    }

    private func begin(total: Int) {
        busy = true
        done = 0
        self.total = total
    }

    private nonisolated static func read(_ entry: IconEntry) -> GraphicDocument? {
        guard let data = try? Data(contentsOf: entry.url) else { return nil }
        return try? SVGReader.read(data)
    }
}
