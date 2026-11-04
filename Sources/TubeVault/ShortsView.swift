import AVKit
import SwiftUI

/// Everything drawn over a Short (buttons, caption, progress bar) is this much bigger than the usual macOS sizes.
private let shortsScale: CGFloat = 1.8
private func sized(_ value: CGFloat) -> CGFloat { value * shortsScale }

/// Downloaded Shorts as a vertical feed: one Short per page, scroll (or ↑ ↓) to move between them.
/// The visible Short loops; the rest stay paused.
struct ShortsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var current: String?
    @AppStorage("shortsMuted") private var muted = false
    @AppStorage("shortsVolume") private var volume = 1.0
    /// Bumped by the space bar; the Short on screen pauses or plays.
    @State private var pauseToggle = 0
    @State private var flick = FlickScroller()
    @FocusState private var focused: Bool

    var body: some View {
        let shorts = store.videos(for: .shorts)
        Group {
            if shorts.isEmpty {
                ContentUnavailableView {
                    Label("No Shorts Yet", systemImage: "film.stack")
                } description: {
                    Text("On a YouTube Short, click Save above the like button. Saved Shorts show up here to scroll through offline.")
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
                        ShortPage(video: video, isActive: current == video.id, muted: $muted, volume: $volume,
                                  pauseToggle: pauseToggle)
                            .padding(.top, top)
                            .frame(width: geo.size.width, height: geo.size.height + top)
                            .id(video.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(0, for: .scrollContent)
            // Scrolling is handled by FlickScroller: a small flick moves one Short, like YouTube.
            .scrollDisabled(true)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
            .overlay(alignment: .trailing) { arrows(shorts) }
            .onAppear { flick.frame = geo.frame(in: .global) }
            .onChange(of: geo.frame(in: .global)) { _, frame in flick.frame = frame }
        }
        .background(Color.black)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { step(1, in: shorts); return .handled }
        .onKeyPress(.upArrow) { step(-1, in: shorts); return .handled }
        .onKeyPress(.space) { pauseToggle += 1; return .handled }
        .onKeyPress(characters: .init(charactersIn: "kK")) { _ in pauseToggle += 1; return .handled }
        .onKeyPress(characters: .init(charactersIn: "mM")) { _ in muted.toggle(); return .handled }
        .onAppear {
            flick.onStep = { step($0, in: shorts) }
            flick.start()
            focused = true
            // Carry on from the Short watched last, even after quitting.
            let last = ui.currentShort ?? UserDefaults.standard.string(forKey: "lastShort")
            if let id = last, shorts.contains(where: { $0.id == id }) {
                current = id
            } else if current == nil {
                current = shorts.first?.id
            }
        }
        .onChange(of: ui.currentShort) { _, id in
            if let id { withAnimation { current = id } }
        }
        .onChange(of: shorts.map(\.id)) { flick.onStep = { step($0, in: shorts) } }
        .onDisappear { flick.stop() }
        .onChange(of: current) { _, id in
            ui.currentShort = id
            if let id { UserDefaults.standard.set(id, forKey: "lastShort") }
        }
    }

    /// Up/down buttons, like YouTube's on desktop, for a mouse without smooth scrolling.
    private func arrows(_ shorts: [Video]) -> some View {
        let index = shorts.firstIndex { $0.id == current } ?? 0
        return VStack(spacing: sized(12)) {
            RoundButton(symbol: "chevron.up", help: "Previous Short (↑)") { step(-1, in: shorts) }
                .disabled(index == 0)
            RoundButton(symbol: "chevron.down", help: "Next Short (↓)") { step(1, in: shorts) }
                .disabled(index >= shorts.count - 1)
        }
        .padding(.trailing, sized(16))
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
    @Binding var volume: Double
    let pauseToggle: Int

    @Environment(LibraryStore.self) private var store
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var paused = false
    @State private var progress = 0.0
    @State private var observer: Any?

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height - 32
            let width = min(height * 9 / 16, geo.size.width - 2 * (sized(44) + sized(16) + 8))
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
        .onChange(of: volume) { _, v in player?.volume = Float(v) }
        .onChange(of: pauseToggle) { if isActive { togglePause() } }
    }

    private var card: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if let player {
                BarePlayerView(player: player)
            }
            // Clicks pass through the player view (see ClickThroughPlayerView) to this layer.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { togglePause() }

            if paused {
                Image(systemName: "play.fill")
                    .font(.system(size: sized(54)))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Caption, like on YouTube.
            VStack(alignment: .leading, spacing: sized(5)) {
                Text(video.channel.isEmpty ? " " : "@\(video.channel)")
                    .font(.system(size: sized(12), weight: .semibold))
                Text(video.title)
                    .font(.system(size: sized(12)))
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, sized(12))
            .padding(.top, sized(36))
            .padding(.bottom, sized(14))
            .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)

            // Playback progress.
            GeometryReader { g in
                Rectangle().fill(.red).frame(width: g.size.width * progress, height: sized(3))
            }
            .frame(height: sized(3))
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Play/pause and volume top left, more top right, like YouTube's Shorts player.
        .overlay(alignment: .topLeading) {
            HStack(spacing: sized(8)) {
                RoundButton(symbol: paused ? "play.fill" : "pause.fill",
                            help: paused ? "Play (space)" : "Pause (space)", small: true) { togglePause() }
                VolumeControl(muted: $muted, volume: $volume)
            }
            .padding(sized(12))
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
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
            .padding(sized(12))
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
        p.volume = Float(volume)
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
        let view = ClickThroughPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

/// Lets clicks fall through to the Short's own tap-to-pause instead of AVKit swallowing them.
private final class ClickThroughPlayerView: AVPlayerView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
            .font(.system(size: sized(16), weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: sized(small ? 40 : 44), height: sized(small ? 40 : 44))
            // Over the video it's dark so it shows on bright Shorts too; beside the feed it's light.
            .background(Circle().fill(small
                ? Color.black.opacity(configuration.isPressed ? 0.6 : 0.4)
                : Color.white.opacity(configuration.isPressed ? 0.3 : 0.16)))
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Circle())
    }
}

/// Speaker button with a slider that slides out on hover, like YouTube's volume control.
private struct VolumeControl: View {
    @Binding var muted: Bool
    @Binding var volume: Double
    @State private var hovering = false

    private var level: Double { muted ? 0 : volume }

    private var symbol: String {
        switch level {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    var body: some View {
        // The pill grows to the right out of the speaker button; the slider is revealed inside it.
        HStack(spacing: 0) {
            Button(action: toggle) {
                Image(systemName: symbol)
                    .frame(width: sized(40), height: sized(40))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(level == 0 ? "Unmute (m)" : "Mute (m)")

            Slider(value: Binding(
                get: { level },
                set: { volume = $0; muted = $0 == 0 }
            ), in: 0...1)
            .controlSize(.small)
            .tint(.white)
            .frame(width: sized(80))
            .padding(.leading, 2)
            .padding(.trailing, sized(14))
            .opacity(hovering ? 1 : 0)
            .frame(width: hovering ? sized(80) + 2 + sized(14) : 0, alignment: .leading)
            .clipped()
            .allowsHitTesting(hovering)
        }
        .font(.system(size: sized(16), weight: .semibold))
        .foregroundStyle(.white)
        .frame(height: sized(40))
        .background(Capsule().fill(.black.opacity(0.4)))
        .clipShape(Capsule())
        .fixedSize()
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hovering = h } }
    }

    private func toggle() {
        if level == 0 {
            muted = false
            if volume == 0 { volume = 0.5 }
        } else {
            muted = true
        }
    }
}

/// Turns a scroll into exactly one Short forward or back: a small trackpad flick or one notch of a
/// mouse wheel is enough, and the rest of that gesture (and its momentum) is swallowed.
@MainActor
private final class FlickScroller {
    var onStep: (Int) -> Void = { _ in }
    /// The feed's area in the window (SwiftUI global coordinates, top-left origin).
    var frame: CGRect = .zero

    private var monitor: Any?
    private var accumulated: CGFloat = 0
    private var stepped = false
    private var lastStep = Date.distantPast

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.covers(event) else { return event }
                self.handle(event)
                return nil
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func covers(_ event: NSEvent) -> Bool {
        guard let window = event.window, let content = window.contentView, window.isKeyWindow || window.isMainWindow
        else { return false }
        let p = event.locationInWindow
        return frame.contains(CGPoint(x: p.x, y: content.frame.height - p.y))
    }

    private func handle(_ event: NSEvent) {
        let trackpad = event.hasPreciseScrollingDeltas
        if event.phase == .began || event.phase == .mayBegin {
            accumulated = 0
            stepped = false
        }
        if !event.momentumPhase.isEmpty { return } // the glide after a flick
        if trackpad && stepped {
            if event.phase == .ended || event.phase == .cancelled { stepped = false }
            return
        }
        // A mouse wheel sends separate notches: one move per short burst.
        if !trackpad && Date().timeIntervalSince(lastStep) < 0.35 { return }

        accumulated += event.scrollingDeltaY
        guard abs(accumulated) >= (trackpad ? 14 : 1) else { return }
        onStep(accumulated < 0 ? 1 : -1)
        accumulated = 0
        stepped = true
        lastStep = Date()
    }
}
