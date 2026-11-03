import SwiftUI

struct ContentView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(DownloadManager.self) private var downloads
    @Environment(UIState.self) private var ui

    @State private var selection: SidebarItem? = .all
    @State private var path: [Video] = []

    var body: some View {
        @Bindable var ui = ui

        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            NavigationStack(path: $path) {
                detail
                    .navigationDestination(for: Video.self) { video in
                        PlayerScreen(video: video) { playNext(after: video) }
                    }
            }
        }
        .onChange(of: selection) { path.removeAll() }
        .onChange(of: ui.openVideoID) { openRequestedVideo() }
        .onChange(of: ui.openLibrary) { _, id in
            guard let id else { return }
            ui.openLibrary = nil
            selection = .library(id)
        }
        .onAppear { openRequestedVideo() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ui.showingAddLink = true
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .help("Download a video from a link (⌘D)")
            }
        }
        .sheet(isPresented: $ui.showingAddLink) {
            AddLinkSheet()
        }
        .sheet(isPresented: $ui.showingSetup) {
            SetupGuideView()
        }
        .overlay(alignment: .bottom) {
            ToastView()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            UpdateBanner()
        }
    }

    /// Jumps to the player for a video requested from YouTube (re-pushed so it seeks again).
    private func openRequestedVideo() {
        guard let id = ui.openVideoID, let video = store.video(id: id) else { return }
        ui.openVideoID = nil
        ui.showingSetup = false
        if video.short {
            ui.openPaused = nil
            ui.currentShort = id
            selection = .shorts
            return
        }
        if selection != .all { selection = .all }
        path.removeAll()
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            path = [video]
        }
    }

    /// A playlist plays straight through, in the order it was picked.
    private func playNext(after video: Video) {
        guard let next = store.nextVideo(after: video) else { return }
        store.setPosition(videoID: next.id, seconds: 0)
        path = [next]
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .all {
        case .downloads:
            DownloadsView()
        case .shorts:
            ShortsView()
        case .all:
            VideoGridView(title: "All Videos", videos: store.videos(for: .all))
        case .unsorted:
            VideoGridView(title: "Unsorted", videos: store.videos(for: .unsorted))
        case .library(let id):
            if let library = store.library(id) {
                VideoGridView(title: library.name, videos: store.videos(for: .library(id)), playlist: library.isPlaylist) {
                    if let first = store.videos(for: .library(id)).first {
                        store.setPosition(videoID: first.id, seconds: 0)
                        path = [first]
                    }
                }
            } else {
                VideoGridView(title: "All Videos", videos: store.videos(for: .all))
            }
        }
    }
}

// MARK: - Add link

struct AddLinkSheet: View {
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download a Video").font(.headline)
                    Text("Paste a YouTube link. It’ll be saved to your TubeVault library for offline viewing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            TextField("https://www.youtube.com/watch?v=…", text: $link)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Download", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if let clip = NSPasteboard.general.string(forType: .string),
               clip.contains("youtu") {
                link = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func submit() {
        guard !link.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        downloads.enqueue(link)
        dismiss()
    }
}

// MARK: - Toast

struct ToastView: View {
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        Group {
            if let notice = downloads.notice {
                Text(notice)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { downloads.notice = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: downloads.notice)
    }
}
