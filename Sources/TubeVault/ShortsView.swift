import AVKit
import SwiftUI

/// Downloaded Shorts as a vertical feed: one Short per page, scroll (or ↑ ↓) to move between them.
/// The visible Short loops; the rest stay paused.
struct ShortsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var current: String?
    @State private var muted = false
    @FocusState private var focused: Bool

    var body: some View {
        let shorts = store.videos(for: .shorts)
        Group {
            if shorts.isEmpty {
                ContentUnavailableView {
                    Label("No Shorts Yet", systemImage: "film.stack")
                } description: {
                    Text("On a YouTube Short, click the ⬇ button at the top right of the player. Saved Shorts show up here to scroll through offline.")
                }
            } else {
                feed(shorts)
            }
        }
        .navigationTitle("Shorts")
    }

    private func feed(_ shorts: [Video]) -> some View {
        // Pages span the whole window, under the toolbar too, so paging lines up exactly;
        // each page keeps its Short clear of the toolbar itself.
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(shorts) { video in
                        ShortPage(video: video, isActive: current == video.id, muted: $muted)
                            .padding(.top, top)
                            .frame(width: geo.size.width, height: geo.size.height + top)
                            .id(video.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(0, for: .scrollContent)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
            .overlay(alignment: .trailing) { arrows(shorts) }
        }
        .background(Color.black)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { step(1, in: shorts); return .handled }
        .onKeyPress(.upArrow) { step(-1, in: shorts); return .handled }
        .onAppear {
            focused = true
            if let id = ui.currentShort, shorts.contains(where: { $0.id == id }) {
                current = id
            } else if current == nil {
                current = shorts.first?.id
            }
        }
        .onChange(of: ui.currentShort) { _, id in
            if let id { withAnimation { current = id } }
        }
        .onChange(of: current) { _, id in ui.currentShort = id }
    }

    /// Up/down buttons, like YouTube's on desktop, for a mouse without smooth scrolling.
    private func arrows(_ shorts: [Video]) -> some View {
        let index = shorts.firstIndex { $0.id == current } ?? 0
        return VStack(spacing: 12) {
            RoundButton(symbol: "chevron.up", help: "Previous Short (↑)") { step(-1, in: shorts) }
                .disabled(index == 0)
            RoundButton(symbol: "chevron.down", help: "Next Short (↓)") { step(1, in: shorts) }
                .disabled(index >= shorts.count - 1)
        }
        .padding(.trailing, 24)
    }

    private func step(_ delta: Int, in shorts: [Video]) {
        let index = shorts.firstIndex { $0.id == current } ?? 0
        let next = min(max(index + delta, 0), shorts.count - 1)
        withAnimation(.easeInOut(duration: 0.3)) { current = shorts[next].id }
    }
}

/// One Short: the vertical video with its title and channel over it. Click to pause.
private struct ShortPage: View {
    let video: Video
    let isActive: Bool
    @Binding var muted: Bool

    @Environment(LibraryStore.self) private var store
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var paused = false
    @State private var progress = 0.0
    @State private var observer: Any?

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height - 32
            let width = min(height * 9 / 16, geo.size.width - 140)
            HStack {
                Spacer(minLength: 0)
                card.frame(width: width, height: height)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear(perform: load)
        .onDisappear(perform: unload)
        .onChange(of: isActive) { _, active in
            if active { paused = false; player?.play() } else { player?.pause() }
        }
        .onChange(of: muted) { _, m in player?.isMuted = m }
    }

    private var card: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if let player {
                BarePlayerView(player: player)
            }

            if paused {
                Image(systemName: "play.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Caption, like on YouTube.
            VStack(alignment: .leading, spacing: 6) {
                Text(video.channel.isEmpty ? " " : "@\(video.channel)")
                    .font(.callout.weight(.semibold))
                Text(video.title)
                    .font(.callout)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 40)
            .padding(.bottom, 18)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)

            // Playback progress.
            GeometryReader { g in
                Rectangle().fill(.red).frame(width: g.size.width * progress, height: 3)
            }
            .frame(height: 3)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { togglePause() }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                RoundButton(symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            help: muted ? "Unmute" : "Mute", small: true) { muted.toggle() }
                Menu {
                    VideoMenu(video: video)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(RoundButtonStyle(small: true))
                .fixedSize()
            }
            .padding(10)
        }
    }

    private func togglePause() {
        guard let player else { return }
        if player.rate == 0 { player.play(); paused = false } else { player.pause(); paused = true }
    }

    private func load() {
        guard player == nil else { return }
        let item = AVPlayerItem(url: store.fileURL(for: video))
        let p = AVQueuePlayer()
        looper = AVPlayerLooper(player: p, templateItem: item)
        p.isMuted = muted
        player = p
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { time in
            MainActor.assumeIsolated {
                let total = p.currentItem?.duration.seconds ?? 0
                progress = total > 0 ? time.seconds / total : 0
            }
        }
        if isActive { p.play() }
    }

    private func unload() {
        player?.pause()
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        looper = nil
        player = nil
        paused = false
    }
}

/// Just the video picture, no controls (the Shorts page draws its own).
private struct BarePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

private struct RoundButton: View {
    let symbol: String
    let help: String
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(RoundButtonStyle(small: small))
            .help(help)
    }
}

private struct RoundButtonStyle: ButtonStyle {
    var small = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 13 : 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: small ? 32 : 44, height: small ? 32 : 44)
            .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.3 : 0.16)))
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Circle())
    }
}
