import Foundation

struct Video: Codable, Identifiable, Hashable {
    var id: String               // YouTube video id
    var title: String
    var channel: String
    var duration: Double?
    var sourceURL: String
    var fileName: String         // relative to Paths.videos
    var thumbnailFileName: String?
    var libraryID: UUID?
    var addedAt: Date
    var fileSize: Int64?
    /// Where playback stopped (seconds), from the in-app player or a pause on YouTube.
    var resumeAt: Double?
    /// A YouTube Short: vertical, shown in the swipeable Shorts feed instead of the grid.
    var isShort: Bool?

    var short: Bool { isShort ?? false }

    var formattedDuration: String? {
        guard let duration, duration > 0 else { return nil }
        return Format.time(duration)
    }
}

struct VideoLibrary: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    /// Set for a YouTube playlist saved from the extension.
    var playlistID: String?
    /// Video ids in the order they were picked on YouTube: the order they download and play in.
    var order: [String]?

    var isPlaylist: Bool { playlistID != nil }
}

enum SidebarItem: Hashable {
    case all
    case shorts
    case unsorted
    case downloads
    case library(UUID)
}

enum Paths {
    /// Everything TubeVault stores lives in ~/Library/Application Support/TubeVault.
    static let support: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TubeVault", isDirectory: true)

    static let videos = support.appendingPathComponent("Videos", isDirectory: true)
    static let thumbnails = support.appendingPathComponent("Thumbnails", isDirectory: true)
    static let database = support.appendingPathComponent("library.json")

    /// Where versions before 1.2 saved videos.
    static let legacyVideos: URL = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TubeVault", isDirectory: true)

    static func ensure() {
        for dir in [support, videos, thumbnails] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Moves videos and thumbnails out of ~/Downloads/TubeVault, then removes that folder.
    /// A loaded Chrome extension folder is left in place so Chrome doesn't lose it.
    static func migrateLegacyFolder() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyVideos.path) else { return }
        ensure()

        func moveContents(of source: URL, to destination: URL) {
            let names = (try? fm.contentsOfDirectory(atPath: source.path)) ?? []
            for name in names where name != ".DS_Store" && name != "Chrome Extension" && name != ".thumbnails" {
                let target = destination.appendingPathComponent(name)
                guard !fm.fileExists(atPath: target.path) else { continue }
                try? fm.moveItem(at: source.appendingPathComponent(name), to: target)
            }
        }
        let legacyThumbs = legacyVideos.appendingPathComponent(".thumbnails", isDirectory: true)
        moveContents(of: legacyThumbs, to: thumbnails)
        moveContents(of: legacyVideos, to: videos)

        let leftover = (try? fm.contentsOfDirectory(atPath: legacyThumbs.path))?.filter { $0 != ".DS_Store" } ?? []
        if leftover.isEmpty { try? fm.removeItem(at: legacyThumbs) }
        let remaining = (try? fm.contentsOfDirectory(atPath: legacyVideos.path))?.filter { $0 != ".DS_Store" } ?? []
        if remaining.isEmpty { try? fm.removeItem(at: legacyVideos) }
    }
}

enum Format {
    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
