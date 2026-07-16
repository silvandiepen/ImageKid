import AVKit
import SwiftUI

struct VideoWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var session: VideoSession
    @State private var hoverControls = false

    var body: some View {
        ZStack {
            Color.black

            VideoPlayer(player: session.player)
                .padding(24)

            VStack {
                HStack {
                    Text(session.sourceURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Basic video viewer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.thinMaterial)

                Spacer()

                FloatingToolbar(canExport: false)
                    .opacity(hoverControls ? 1 : 0)
                    .offset(y: hoverControls ? 0 : 8)
                    .padding(.bottom, 20)
            }
        }
        .onHover { inside in
            hoverControls = inside
        }
        .onDisappear {
            session.player.pause()
        }
        .overlay(alignment: .topTrailing) {
            if appModel.activeTool != .view {
                Text("Video editing tools are scaffolded for the next implementation milestone.")
                    .font(.caption)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(14)
            }
        }
    }
}
