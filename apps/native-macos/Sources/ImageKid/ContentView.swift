import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isDropTarget = false

    private var isVideoSelected: Bool {
        if case .video = appModel.media { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .leading) {
            workspaceContent

            // Images use the dockable Files panel; video keeps the legacy sidebar.
            if !appModel.items.isEmpty, isVideoSelected {
                WorkspaceSidebar(isCollapsed: $appModel.isWorkspaceSidebarCollapsed)
                    .padding(.leading, 18)
                    .padding(.vertical, 18)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(10)
            }

            if appModel.isShowingNewFile {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { appModel.isShowingNewFile = false }
                    NewFilePanel(appModel: appModel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.16), value: appModel.isShowingNewFile)
        .animation(.snappy(duration: 0.22), value: appModel.items.count)
        .animation(.snappy(duration: 0.22), value: appModel.isWorkspaceSidebarCollapsed)
        .background(WindowHeaderConfigurator())
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget, perform: handleDrop)
        .sheet(isPresented: $appModel.isShowingResize) {
            resizeSheet
        }
        .sheet(isPresented: $appModel.isShowingExport) {
            exportSheet
        }
        .sheet(isPresented: $appModel.isShowingCanvasSize) {
            if let session = appModel.imageSession {
                CanvasSizeSheet(appModel: appModel, currentSize: session.effectivePixelSize)
            }
        }
        .sheet(isPresented: $appModel.isShowingPromptEdit) {
            PromptEditSheet(
                isApplying: appModel.isApplyingPromptEdit,
                providerName: appModel.promptEditProviderName,
                hasCredential: appModel.hasPromptEditCredential,
                sendsSelectionOnly: appModel.promptEditSendsSelectionOnly,
                onCancel: { appModel.isShowingPromptEdit = false },
                onApply: { prompt in appModel.applyPromptEdit(prompt: prompt) }
            )
        }
        .sheet(isPresented: $appModel.isShowingEnhance) {
            if case .image(let session) = appModel.media {
                EnhanceSheet(
                    pixelSize: session.croppedPixelSize,
                    isApplying: appModel.isApplyingEnhance,
                    onCancel: { appModel.isShowingEnhance = false },
                    onApply: { quality, size in appModel.applyEnhance(quality: quality, size: size) }
                )
            }
        }
        .alert(
            "ImageKid",
            isPresented: Binding(
                get: { appModel.errorMessage != nil },
                set: { if !$0 { appModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appModel.errorMessage = nil }
        } message: {
            Text(appModel.errorMessage ?? "Unknown error")
        }
        // The one-time "want the Best Quality model?" question. Asked the
        // first time a feature runs without it; "Not Now" is remembered.
        .alert(
            appModel.bestQualityOffer?.title ?? "",
            isPresented: Binding(
                get: { appModel.bestQualityOffer != nil },
                set: { if !$0 { appModel.declineBestQualityOffer() } }
            )
        ) {
            Button("Download Best Quality") { appModel.acceptBestQualityOffer() }
            Button("Not Now", role: .cancel) { appModel.declineBestQualityOffer() }
        } message: {
            Text(appModel.bestQualityOffer?.message ?? "")
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        Group {
                switch appModel.media {
                case .image(let session):
                    ImageWorkspaceView(session: session, panelDock: appModel.panelDock)
                case .video(let session):
                    VideoWorkspaceView(session: session)
                case nil:
                    EmptyStateView(isDropTarget: isDropTarget, openAction: {
                        appModel.openPanel()
                    }, newAction: {
                        appModel.isShowingNewFile = true
                    }, openURLAction: { url in
                        appModel.load([url])
                    })
                }
        }
    }

    @ViewBuilder
    private var resizeSheet: some View {
        switch appModel.media {
        case .image(let session):
            ResizeSheet(
                originalSize: session.effectivePixelSize,
                currentSize: session.outputSize
            ) { size in
                session.outputSize = size
                session.isDirty = true
            }
        case .video(let session):
            ResizeSheet(
                originalSize: session.naturalSize,
                currentSize: session.outputSize
            ) { size in
                session.outputSize = size
            }
        case nil:
            Text("Open an image or video first.")
                .padding(32)
        }
    }

    @ViewBuilder
    private var exportSheet: some View {
        switch appModel.media {
        case .image(let session):
            ExportSheet(
                imageSize: session.effectivePixelSize,
                initialFormat: session.sourceURL.flatMap(ImageExportFormat.init(url:)) ?? .png,
                itemCount: max(1, appModel.exportTargetItems.count)
            ) { options in
                appModel.exportImage(options: options)
            }
        case .video:
            Text("Video export is not implemented yet.")
                .padding(32)
        case nil:
            Text("Open an image first.")
                .padding(32)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard error == nil else { return }

                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else {
                    url = nil
                }

                guard let url else { return }
                Task { @MainActor in appModel.load(url) }
            }
        }
        return true
    }
}

private struct WindowHeaderConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: view.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
    }
}
