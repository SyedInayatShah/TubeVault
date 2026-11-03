import AVKit
import SwiftUI

struct PlayerScreen: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui
    let video: Video
    /// Called when the video plays to the end (a playlist moves on to its next video).
    var onEnded: () -> Void = {}

    @State private var player: AVPlayer?
    @State private var autosave: Any?

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
                    if let playlist = playlistPosition {
                        Label(playlist, systemImage: "list.number")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
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
        .onAppear(perform: start)
        .onDisappear {
            savePosition()
            player?.pause()
            if let autosave { player?.removeTimeObserver(autosave) }
            autosave = nil
            player = nil
        }
        // Closing the window or quitting doesn't always tear the view down first.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in savePosition() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in savePosition() }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            onEnded()
        }
    }

    /// "Playlist name · 3 of 12 · Next: title" for a video in a saved playlist.
    private var playlistPosition: String? {
        guard let library = store.library(video.libraryID), library.isPlaylist else { return nil }
        let list = store.videos(for: .library(library.id))
        guard let i = list.firstIndex(where: { $0.id == video.id }) else { return nil }
        var text = "\(library.name) · \(i + 1) of \(list.count)"
        if i + 1 < list.count { text += " · Next: \(list[i + 1].title)" }
        return text
    }

    private func start() {
        let p = AVPlayer(url: store.fileURL(for: video))
        player = p
        // Handed over from a pause on YouTube: wait there. Otherwise carry on from the saved spot.
        let paused = ui.openPaused == video.id
        ui.openPaused = nil
        if let t = store.video(id: video.id)?.resumeAt {
            p.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                if !paused { p.play() }
            }
        } else if !paused {
            p.play()
        }
        // Keep the spot saved while watching, in case the app is closed abruptly.
        autosave = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { _ in
            MainActor.assumeIsolated {
                if p.rate != 0 { savePosition() }
            }
        }
    }

    private func savePosition() {
        guard let p = player else { return }
        let seconds = p.currentTime().seconds
        guard seconds.isFinite else { return }
        store.setPosition(videoID: video.id, seconds: seconds)
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
