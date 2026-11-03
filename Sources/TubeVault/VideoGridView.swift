import SwiftUI

struct VideoGridView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    let title: String
    let videos: [Video]
    /// A saved YouTube playlist: shown in its picked order, numbered, with Play All.
    var playlist = false
    var playAll: () -> Void = {}

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case title = "Title"
        case duration = "Duration"
        case playlist = "Playlist Order"
        var id: Self { self }
    }

    @State private var search = ""
    @AppStorage("sortOrder") private var librarySort: SortOrder = .newest
    @AppStorage("playlistSortOrder") private var playlistSort: SortOrder = .playlist

    private var sort: SortOrder {
        get { playlist ? playlistSort : (librarySort == .playlist ? .newest : librarySort) }
        nonmutating set { if playlist { playlistSort = newValue } else { librarySort = newValue } }
    }

    private var shown: [Video] {
        let filtered = search.isEmpty ? videos : videos.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
                $0.channel.localizedCaseInsensitiveContains(search)
        }
        switch sort {
        case .playlist: return filtered
        case .newest: return filtered.sorted { $0.addedAt > $1.addedAt }
        case .oldest: return filtered.sorted { $0.addedAt < $1.addedAt }
        case .title: return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .duration: return filtered.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
        }
    }

    var body: some View {
        Group {
            if videos.isEmpty {
                ContentUnavailableView {
                    Label("No Videos Yet", systemImage: "play.rectangle")
                } description: {
                    Text("Right-click a YouTube video in your browser and choose **Download with TubeVault**, or press ⌘D to paste a link. Downloaded videos play offline.")
                } actions: {
                    Button("Download from Link…") { ui.showingAddLink = true }
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 20)], spacing: 24) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, video in
                            NavigationLink(value: video) {
                                VideoCard(video: video, number: playlist && sort == .playlist && search.isEmpty ? index + 1 : nil)
                            }
                            .buttonStyle(.plain)
                            .draggable(video.id)
                            .contextMenu { VideoMenu(video: video) }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .searchable(text: $search, placement: .toolbar, prompt: "Search videos")
        .toolbar {
            if playlist && !videos.isEmpty {
                ToolbarItem {
                    Button(action: playAll) {
                        Label("Play All", systemImage: "play.fill")
                    }
                    .help("Play the playlist from the start, in order")
                }
            }
            ToolbarItem {
                Menu {
                    Picker("Sort", selection: Binding(get: { sort }, set: { sort = $0 })) {
                        ForEach(SortOrder.allCases.filter { playlist || $0 != .playlist }) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort videos")
            }
        }
    }

    private var subtitle: String {
        let total = videos.compactMap(\.fileSize).reduce(0, +)
        let count = "\(videos.count) video\(videos.count == 1 ? "" : "s")"
        return total > 0 ? "\(count) · \(Format.bytes(total))" : count
    }
}

// MARK: - Card

struct VideoCard: View {
    @Environment(LibraryStore.self) private var store
    let video: Video
    /// Position in a playlist, shown on the thumbnail.
    var number: Int?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    ThumbnailImage(url: store.thumbnailURL(for: video))
                }
                .clipped()
                .overlay {
                Color.black.opacity(hovering ? 0.25 : 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
                    .opacity(hovering ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.8)
            }
            .overlay(alignment: .topLeading) {
                if let number {
                    Text("\(number)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(minWidth: 24, minHeight: 24)
                        .padding(.horizontal, number > 9 ? 4 : 0)
                        .background(.black.opacity(0.75), in: Capsule())
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let d = video.formattedDuration {
                    Text(d)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                }
            }
            .overlay(alignment: .bottom) {
                // Watched-so-far bar, like YouTube's.
                if let t = video.resumeAt, let d = video.duration, d > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.35))
                            Rectangle().fill(Color.red).frame(width: geo.size.width * min(t / d, 1))
                        }
                    }
                    .frame(height: 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(hovering ? 0.25 : 0.1), radius: hovering ? 12 : 4, y: hovering ? 6 : 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(video.channel)
                    if let lib = store.library(video.libraryID) {
                        Text("·")
                        Label(lib.name, systemImage: lib.isPlaylist ? "list.number" : "folder").labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}

struct VideoMenu: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui
    let video: Video

    var body: some View {
        Menu("Move to Library") {
            Button {
                store.move(videoID: video.id, to: nil)
            } label: {
                Label("Unsorted", systemImage: video.libraryID == nil ? "checkmark" : "tray")
            }
            if !store.libraries.isEmpty { Divider() }
            ForEach(store.libraries) { lib in
                Button {
                    store.move(videoID: video.id, to: lib.id)
                } label: {
                    Label(lib.name, systemImage: video.libraryID == lib.id ? "checkmark" : "folder")
                }
            }
            Divider()
            Button("New Library…") { ui.showingNewLibrary = true }
        }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: video)])
        }
        Button("Open on YouTube") {
            if let url = URL(string: video.sourceURL) { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button("Delete Download", role: .destructive) {
            store.delete(video)
        }
    }
}

// MARK: - Thumbnails

struct ThumbnailImage: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: url) {
            image = await ThumbnailCache.shared.image(for: url)
        }
    }
}

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache: [URL: NSImage] = [:]

    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let hit = cache[url] { return hit }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache[url] = image
        return image
    }
}
