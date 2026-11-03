import AVKit
import SwiftUI

struct PlayerScreen: View {
    @Environment(LibraryStore.self) private var store
    let video: Video

    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let player {
                    PlayerView(player: player)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(video.channel)
                        if let d = video.formattedDuration { Text("·"); Text(d) }
                        if let size = video.fileSize { Text("·"); Text(Format.bytes(size)) }
                        Text("·")
                        Label("Available offline", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    VideoMenu(video: video)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(16)
            .background(.bar)
        }
        .navigationTitle(video.title)
        .onAppear {
            let p = AVPlayer(url: store.fileURL(for: video))
            player = p
            // Saved spot (from here or a pause on YouTube): open paused right there.
            if let t = store.video(id: video.id)?.resumeAt {
                p.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                p.play()
            }
        }
        .onDisappear {
            if let p = player {
                p.pause()
                store.setPosition(videoID: video.id, seconds: p.currentTime().seconds)
            }
            player = nil
        }
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
