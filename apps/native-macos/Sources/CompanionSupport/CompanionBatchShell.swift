import SwiftUI
import UniformTypeIdentifiers

struct CompanionBatchShell<Settings: View>: View {
    let title: String
    let primaryActionTitle: String
    let isProcessing: Bool
    let items: [BatchItem]
    let progress: Double
    let existingResultCount: Int
    let acceptsDrop: ([URL]) -> Void
    let openFiles: () -> Void
    let clearCompleted: () -> Void
    let removeItems: (Set<BatchItem.ID>) -> Void
    let resetItems: (Set<BatchItem.ID>) -> Void
    /// Nil in apps that have nothing to inspect per image.
    var openEditor: ((BatchItem) -> Void)?
    let primaryAction: (CompanionBatchModel.ExistingResultPolicy) -> Void
    let cancelAction: () -> Void
    @ViewBuilder var settings: Settings

    @State private var isDropTargeted = false
    @State private var selection: Set<BatchItem.ID> = []
    @State private var isAskingAboutExistingResults = false

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            HStack(spacing: 0) {
                sidebar
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The window hides its title bar but still reserves the space, so without this
        // the strip below stacks on top of that inset and the header is twice as tall
        // as it looks in the code.
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 900, minHeight: 620)
        .background {
            VisualEffectBackground()
                .overlay(Color.black.opacity(0.50))
                .ignoresSafeArea()
        }
        .background(CompanionWindowAccessor())
        .preferredColorScheme(.dark)
        .overlay { dropHighlight }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            loadDroppedURLs(from: providers)
            return true
        }
        .onChange(of: items) { _, newItems in
            selection = selection.filter { id in newItems.contains { $0.id == id } }
        }
        .confirmationDialog(
            existingResultCount == 1
                ? "1 image already has a result"
                : "\(existingResultCount) images already have a result",
            isPresented: $isAskingAboutExistingResults,
            titleVisibility: .visible
        ) {
            Button("Overwrite Them") { primaryAction(.overwrite) }
            Button("Skip Them") { primaryAction(.skip) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their files are already in the destination folder.")
        }
    }

    // MARK: - Chrome

    /// Sits in the window's own title-bar strip, beside the traffic lights.
    private var titleBar: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    settings
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            controls
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.24))
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 14) {
            if items.isEmpty {
                emptyState
            } else {
                queueHeader
                queueList
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.10))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if isProcessing {
                ProgressView(value: progress)
                Button(role: .cancel, action: cancelAction) {
                    wideLabel("Stop Batch")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    if existingResultCount > 0 {
                        isAskingAboutExistingResults = true
                    } else {
                        primaryAction(.overwrite)
                    }
                } label: {
                    wideLabel(primaryActionTitle)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(items.isEmpty)

                Button(action: clearCompleted) {
                    wideLabel("Clear Finished")
                }
                .buttonStyle(.bordered)
                .disabled(!items.contains(where: \.isDone))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A bordered button sizes its chrome to its label, so widening the button's own
    /// frame leaves the pill centred. The label is what has to stretch.
    private func wideLabel(_ text: String) -> some View {
        Text(text).frame(maxWidth: .infinity)
    }

    // MARK: - Queue

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.tint)
            Text("Drop images anywhere in this window")
                .font(.title3.weight(.semibold))
            Button {
                openFiles()
            } label: {
                Label("Choose Images", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var queueHeader: some View {
        HStack(spacing: 12) {
            Text(queueSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if !selection.isEmpty {
                Button("Try Again") {
                    resetItems(selection)
                }
                .buttonStyle(.borderless)
                .disabled(isProcessing || selectedItems.allSatisfy { $0.state == .waiting })
                Button("Remove \(selection.count)") {
                    removeItems(selection)
                }
                .buttonStyle(.borderless)
                .disabled(isProcessing)
            }
            Button {
                openFiles()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    private var selectedItems: [BatchItem] {
        items.filter { selection.contains($0.id) }
    }

    private var queueSummary: String {
        var parts = ["\(items.count) images"]
        let finished = items.filter(\.isDone).count
        if finished > 0 {
            parts.append("\(finished) finished")
        }
        let existing = items.filter { $0.hasExistingResult && !$0.isDone }.count
        if existing > 0 {
            parts.append("\(existing) already in destination")
        }
        return parts.joined(separator: " · ")
    }

    private var queueList: some View {
        List(selection: $selection) {
            ForEach(items) { item in
                BatchQueueRow(item: item, openEditor: openEditor) {
                    removeItems([item.id])
                }
                .tag(item.id)
                // No gesture of any kind on the row: a `List` row hands its clicks to
                // the table view underneath, and any SwiftUI gesture here — even a
                // simultaneous double-tap — takes the mouse-down that selection needs.
                // The editor opens from the thumbnail, the row button, or this menu.
                .contextMenu {
                    rowMenu(for: item)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDeleteCommand {
            removeItems(selection)
        }
    }

    @ViewBuilder private func rowMenu(for item: BatchItem) -> some View {
        let targets = actionTargets(for: item)
        if let openEditor {
            Button("Compare and Edit...") { openEditor(item) }
            Divider()
        }
        let results = targets.compactMap(\.outputURL)
        if !results.isEmpty {
            Button("Open Result") {
                CompanionFileActions.open(results)
            }
            Button("Reveal Result in Finder") {
                CompanionFileActions.revealInFinder(results)
            }
        }
        Button("Open Original") {
            CompanionFileActions.open(targets.map(\.sourceURL))
        }
        Button("Reveal Original in Finder") {
            CompanionFileActions.revealInFinder(targets.map(\.sourceURL))
        }
        Divider()
        Button(targets.contains(where: \.isDone) ? "Put Back in Queue" : "Try Again") {
            resetItems(Set(targets.map(\.id)))
        }
        .disabled(isProcessing || targets.allSatisfy { $0.state == .waiting })
        Button("Remove from Queue") {
            removeItems(Set(targets.map(\.id)))
        }
        .disabled(isProcessing)
    }

    /// A context-menu action applies to the whole selection when the clicked row is
    /// part of it, and to just that row otherwise — the standard Finder behaviour.
    private func actionTargets(for item: BatchItem) -> [BatchItem] {
        guard selection.contains(item.id) else { return [item] }
        return items.filter { selection.contains($0.id) }
    }

    // MARK: - Drop

    @ViewBuilder private var dropHighlight: some View {
        if isDropTargeted {
            ZStack {
                Color.accentColor.opacity(0.14)
                Text("Drop to add images")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func loadDroppedURLs(from providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url {
                    Task { @MainActor in
                        acceptsDrop([url])
                    }
                }
            }
        }
    }
}

private struct BatchQueueRow: View {
    let item: BatchItem
    let openEditor: ((BatchItem) -> Void)?
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            preview
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.outputSizeLabel.map { "\(item.sizeLabel) → \($0)" } ?? item.sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                status
                if let note = item.sourceActionNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(item.sourceActionFailed ? .orange : .secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            actions
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var preview: some View {
        if let openEditor {
            Button {
                openEditor(item)
            } label: {
                previewImage
            }
            .buttonStyle(.plain)
            .help("Compare with the original and correct the cutout")
        } else {
            previewImage
        }
    }

    @ViewBuilder private var previewImage: some View {
        Group {
            if let image = item.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(2)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 58, height: 58)
        .background {
            if item.isDone {
                CheckerboardBackground()
            } else {
                Color.white.opacity(0.06)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 2) {
            if let openEditor {
                Button {
                    openEditor(item)
                } label: {
                    Image(systemName: "rectangle.righthalf.inset.filled.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Compare with the original and correct the cutout")
            }

            if item.isDone {
                Button {
                    if let outputURL = item.outputURL {
                        CompanionFileActions.open([outputURL])
                    }
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Open the result")

                Button {
                    if let outputURL = item.outputURL {
                        CompanionFileActions.revealInFinder([outputURL])
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal the result in Finder")
            }

            Button(action: remove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Remove from queue")
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var status: some View {
        switch item.state {
        case .waiting:
            if item.hasExistingResult {
                Text("Already in the destination folder")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Waiting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .skipped:
            Text("Skipped — already in the destination folder")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .processing(let detail, let fraction):
            VStack(alignment: .leading, spacing: 4) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tint)
                if let fraction {
                    ProgressView(value: fraction)
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        case .done(let url):
            Text("Saved as \(url.lastPathComponent)")
                .font(.caption)
                .foregroundStyle(.green)
                .lineLimit(1)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
