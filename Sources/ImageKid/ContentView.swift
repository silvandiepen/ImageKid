import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isDropTarget = false

    var body: some View {
        Group {
            switch appModel.media {
            case .image(let session):
                ImageWorkspaceView(session: session)
            case .video(let session):
                VideoWorkspaceView(session: session)
            case nil:
                EmptyStateView(isDropTarget: isDropTarget) {
                    appModel.openPanel()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget, perform: handleDrop)
        .sheet(isPresented: $appModel.isShowingResize) {
            resizeSheet
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

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
        return true
    }
}
