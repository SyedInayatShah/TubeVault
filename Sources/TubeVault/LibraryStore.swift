import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    private(set) var videos: [Video] = []
    private(set) var libraries: [VideoLibrary] = []

    private struct Snapshot: Codable {
        var videos: [Video]
        var libraries: [VideoLibrary]
    }

    init() {
        Paths.ensure()
        Paths.migrateLegacyFolder()
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Paths.database),
              let snapshot = try? JSONDecoder.iso.decode(Snapshot.self, from: data) else { return }
        libraries = snapshot.libraries
        videos = snapshot.videos
        pruneMissingFiles()
    }

    private func save() {
        let snapshot = Snapshot(videos: videos, libraries: libraries)
        guard let data = try? JSONEncoder.iso.encode(snapshot) else { return }
        try? data.write(to: Paths.database, options: .atomic)
    }

    /// Only videos whose file is actually on disk are shown.
    func pruneMissingFiles() {
        let before = videos.count
        videos.removeAll { !FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        if videos.count != before { save() }
    }

    // MARK: Files

    func fileURL(for video: Video) -> URL {
        Paths.videos.appendingPathComponent(video.fileName)
    }

    func thumbnailURL(for video: Video) -> URL? {
        video.thumbnailFileName.map { Paths.thumbnails.appendingPathComponent($0) }
    }

    func contains(videoID: String) -> Bool {
        videos.contains { $0.id == videoID }
    }

    // MARK: Videos

    func add(_ video: Video) {
        videos.removeAll { $0.id == video.id }
        videos.insert(video, at: 0)
        save()
    }

    func move(videoID: String, to libraryID: UUID?) {
        guard let i = videos.firstIndex(where: { $0.id == videoID }) else { return }
        videos[i].libraryID = libraryID
        save()
    }

    func delete(_ video: Video) {
        try? FileManager.default.removeItem(at: fileURL(for: video))
        if let thumb = thumbnailURL(for: video) {
            try? FileManager.default.removeItem(at: thumb)
        }
        videos.removeAll { $0.id == video.id }
        save()
    }

    func video(id: String) -> Video? {
        videos.first { $0.id == id }
    }

    /// Remembers the playback position; clears it near the start or end.
    func setPosition(videoID: String, seconds: Double) {
        guard let i = videos.firstIndex(where: { $0.id == videoID }) else { return }
        let duration = videos[i].duration ?? .infinity
        videos[i].resumeAt = (seconds < 2 || seconds > duration - 3) ? nil : seconds
        save()
    }

    func videos(for item: SidebarItem) -> [Video] {
        switch item {
        case .all: videos
        case .unsorted: videos.filter { $0.libraryID == nil }
        case .library(let id): videos.filter { $0.libraryID == id }
        case .downloads: []
        }
    }

    func count(in libraryID: UUID) -> Int {
        videos.lazy.filter { $0.libraryID == libraryID }.count
    }

    // MARK: Libraries

    @discardableResult
    func createLibrary(named name: String) -> VideoLibrary {
        let library = VideoLibrary(name: name.trimmingCharacters(in: .whitespaces))
        libraries.append(library)
        save()
        return library
    }

    func rename(_ libraryID: UUID, to name: String) {
        guard let i = libraries.firstIndex(where: { $0.id == libraryID }) else { return }
        libraries[i].name = name.trimmingCharacters(in: .whitespaces)
        save()
    }

    /// Deleting a library keeps its videos; they go back to Unsorted.
    func deleteLibrary(_ libraryID: UUID) {
        libraries.removeAll { $0.id == libraryID }
        for i in videos.indices where videos[i].libraryID == libraryID {
            videos[i].libraryID = nil
        }
        save()
    }

    func library(_ id: UUID?) -> VideoLibrary? {
        libraries.first { $0.id == id }
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
