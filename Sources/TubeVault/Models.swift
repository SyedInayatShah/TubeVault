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

    var formattedDuration: String? {
        guard let duration, duration > 0 else { return nil }
        return Format.time(duration)
    }
}

struct VideoLibrary: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var createdAt = Date()
}

enum SidebarItem: Hashable {
    case all
    case unsorted
    case downloads
    case library(UUID)
}

enum Paths {
    /// Videos live in ~/Downloads/TubeVault so they are visible in Finder too.
    static let videos: URL = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TubeVault", isDirectory: true)

    static let thumbnails = videos.appendingPathComponent(".thumbnails", isDirectory: true)

    static let support: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TubeVault", isDirectory: true)

    static let database = support.appendingPathComponent("library.json")

    static func ensure() {
        for dir in [videos, thumbnails, support] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
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
