import AppKit
import AVFoundation
import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class DownloadTask: Identifiable {
    enum State: Equatable {
        case starting
        case downloading
        case finishing
        case failed(String)
    }

    let id = UUID()
    let url: String
    var videoID: String?
    var title: String
    var channel = ""
    var duration: Double?
    var thumbnail: URL?
    var progress: Double = 0
    var speed: Double?
    var eta: Double?
    var state: State = .starting

    @ObservationIgnored var process: Process?
    @ObservationIgnored var cancelled = false
    @ObservationIgnored var parts = 1
    @ObservationIgnored var partIndex = 0
    @ObservationIgnored var lastFraction = 0.0
    @ObservationIgnored var outputPath: String?
    @ObservationIgnored var thumbnailJob: Task<String?, Never>?

    init(url: String) {
        self.url = url
        self.title = url
    }

    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    func reset() {
        state = .starting
        progress = 0
        speed = nil
        eta = nil
        parts = 1
        partIndex = 0
        lastFraction = 0
        outputPath = nil
        cancelled = false
    }
}

@MainActor
@Observable
final class DownloadManager {
    private(set) var tasks: [DownloadTask] = []
    /// Short message shown as a toast in the main window.
    var notice: String?
    /// Video paused on YouTube most recently; opened at that spot when the app is next brought forward.
    var resumeRequest: String?

    private let store: LibraryStore
    /// Pause positions reported for videos that are still downloading.
    private var pendingPositions: [String: Double] = [:]

    init(store: LibraryStore) {
        self.store = store
    }

    var activeTasks: [DownloadTask] { tasks.filter { !$0.isFailed } }

    var overallProgress: Double? {
        let active = activeTasks
        guard !active.isEmpty else { return nil }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }

    // MARK: Public API

    func enqueue(_ raw: String) {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: link),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            notice = "That doesn’t look like a video link."
            return
        }
        if let id = Self.youtubeID(from: url), store.contains(videoID: id) {
            notice = "Already in your library."
            return
        }
        if tasks.contains(where: { $0.url == link && !$0.isFailed }) {
            notice = "Already downloading."
            return
        }
        let task = DownloadTask(url: link)
        tasks.append(task)
        notice = "Download started."
        Task { await run(task) }
    }

    /// Called when the video is paused on YouTube.
    func recordPosition(videoID: String, seconds: Double) {
        if store.contains(videoID: videoID) {
            store.setPosition(videoID: videoID, seconds: seconds)
        } else {
            pendingPositions[videoID] = seconds
        }
        resumeRequest = videoID
    }

    func retry(_ task: DownloadTask) {
        task.reset()
        Task { await run(task) }
    }

    func cancel(_ task: DownloadTask, removePartialFiles: Bool = true) {
        task.cancelled = true
        task.process?.terminate()
        task.thumbnailJob?.cancel()
        tasks.removeAll { $0.id == task.id }
        if removePartialFiles, let id = task.videoID {
            Self.removePartialFiles(for: id)
        }
    }

    func remove(_ task: DownloadTask) {
        tasks.removeAll { $0.id == task.id }
    }

    func cancelAll() {
        for task in tasks { cancel(task) }
    }

    // MARK: Running yt-dlp

    private func run(_ task: DownloadTask) async {
        guard let ytdlp = Tools.path(for: "yt-dlp") else {
            task.state = .failed("yt-dlp isn’t installed. In Terminal run: brew install yt-dlp ffmpeg")
            return
        }
        Paths.ensure()

        var args = [
            "--no-playlist",
            "--quiet", "--progress", "--newline", "--no-colors",
            // Prefer H.264 + AAC so AVKit can play the file natively.
            "-f", "bv*+ba/b",
            "-S", "vcodec:h264,res:1080,acodec:m4a",
            "--merge-output-format", "mp4",
            "--progress-template",
            "download:TVP %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s %(progress.speed)s %(progress.eta)s",
            "--print", "before_dl:TVINFO %(.{id,title,channel,uploader,duration,thumbnail})j",
            "--print", "before_dl:TVPARTS %(requested_formats.:.format_id)j",
            "--print", "after_move:TVFILE %(filepath)s",
            "-o", Paths.videos.path + "/%(title).80B [%(id)s].%(ext)s",
        ]
        if let ffmpeg = Tools.path(for: "ffmpeg") {
            args += ["--ffmpeg-location", ffmpeg]
        }
        args.append(task.url)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.arguments = args
        process.environment = Tools.environment
        task.process = process

        let result: ProcessRunner.Result
        do {
            result = try await ProcessRunner.run(process) { [weak self] line in
                await self?.handle(line, for: task)
            }
        } catch {
            task.state = .failed(error.localizedDescription)
            return
        }

        if task.cancelled { return }

        guard result.status == 0, let path = task.outputPath,
              FileManager.default.fileExists(atPath: path) else {
            task.state = .failed(Self.errorMessage(from: result.stderr))
            return
        }
        await finish(task, filePath: path)
    }

    private func handle(_ line: String, for task: DownloadTask) {
        guard !task.cancelled else { return }
        if line.hasPrefix("TVP ") {
            updateProgress(task, fields: line.dropFirst(4).split(separator: " "))
        } else if line.hasPrefix("TVINFO ") {
            applyInfo(task, json: String(line.dropFirst(7)))
        } else if line.hasPrefix("TVPARTS ") {
            let json = Data(line.dropFirst(8).utf8)
            if let ids = try? JSONSerialization.jsonObject(with: json) as? [Any], !ids.isEmpty {
                task.parts = ids.count
            }
        } else if line.hasPrefix("TVFILE ") {
            task.outputPath = String(line.dropFirst(7))
        }
    }

    private func applyInfo(_ task: DownloadTask, json: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return }
        let id = obj["id"] as? String
        task.videoID = id
        task.title = obj["title"] as? String ?? task.title
        task.channel = (obj["channel"] as? String) ?? (obj["uploader"] as? String) ?? ""
        task.duration = obj["duration"] as? Double
        task.thumbnail = (obj["thumbnail"] as? String).flatMap(URL.init(string:))
        task.state = .downloading

        if let id, store.contains(videoID: id) {
            notice = "“\(task.title)” is already in your library."
            cancel(task, removePartialFiles: false)
            return
        }
        if let id, let remote = task.thumbnail {
            task.thumbnailJob = Task { await Self.saveThumbnail(from: remote, videoID: id) }
        }
    }

    private func updateProgress(_ task: DownloadTask, fields: [Substring]) {
        guard fields.count >= 5 else { return }
        let done = Double(fields[0]) ?? 0
        guard let total = Double(fields[1]) ?? Double(fields[2]), total > 0 else { return }
        let fraction = min(done / total, 1)

        // Video and audio are downloaded one after another; a reset means the next part began.
        if fraction + 0.3 < task.lastFraction, task.partIndex < task.parts - 1 {
            task.partIndex += 1
        }
        task.lastFraction = fraction
        task.progress = min((Double(task.partIndex) + fraction) / Double(task.parts), 1)
        task.speed = Double(fields[3])
        task.eta = Double(fields[4])
        task.state = (task.partIndex == task.parts - 1 && fraction >= 1) ? .finishing : .downloading
    }

    private func finish(_ task: DownloadTask, filePath: String) async {
        task.state = .finishing
        task.progress = 1
        let fileURL = URL(fileURLWithPath: filePath)
        let id = task.videoID ?? UUID().uuidString

        var thumbName = await task.thumbnailJob?.value
        if thumbName == nil {
            thumbName = await Self.generateThumbnail(for: fileURL, videoID: id)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? NSNumber)?.int64Value

        store.add(Video(
            id: id,
            title: task.title,
            channel: task.channel,
            duration: task.duration,
            sourceURL: task.url,
            fileName: fileURL.lastPathComponent,
            thumbnailFileName: thumbName,
            libraryID: nil,
            addedAt: Date(),
            fileSize: size
        ))
        if let seconds = pendingPositions.removeValue(forKey: id) {
            store.setPosition(videoID: id, seconds: seconds)
        }
        tasks.removeAll { $0.id == task.id }
        Self.notifyFinished(title: task.title)
    }

    // MARK: Helpers

    static func youtubeID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.hasSuffix("youtu.be") {
            return url.pathComponents.dropFirst().first
        }
        guard host.hasSuffix("youtube.com") else { return nil }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        let parts = url.pathComponents
        if let i = parts.firstIndex(where: { ["shorts", "live", "embed"].contains($0) }), i + 1 < parts.count {
            return parts[i + 1]
        }
        return nil
    }

    private static func errorMessage(from stderr: String) -> String {
        let lines = stderr.split(separator: "\n").map(String.init)
        if let err = lines.last(where: { $0.hasPrefix("ERROR:") }) {
            return err.replacingOccurrences(of: "ERROR: ", with: "")
        }
        return lines.last ?? "Download failed. Check your internet connection."
    }

    private static func removePartialFiles(for videoID: String) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Paths.videos.path) else { return }
        for name in names where name.contains("[\(videoID)]") {
            try? fm.removeItem(at: Paths.videos.appendingPathComponent(name))
        }
    }

    nonisolated private static func saveThumbnail(from remote: URL, videoID: String) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(from: remote),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data),
              let jpeg = image.jpegData() else { return nil }
        let name = "\(videoID).jpg"
        do {
            try jpeg.write(to: Paths.thumbnails.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// Offline fallback: grab a frame from the downloaded file.
    nonisolated private static func generateThumbnail(for file: URL, videoID: String) async -> String? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 540)
        guard let (cg, _) = try? await generator.image(at: CMTime(seconds: 3, preferredTimescale: 600)) else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        guard let jpeg = image.jpegData() else { return nil }
        let name = "\(videoID).jpg"
        try? jpeg.write(to: Paths.thumbnails.appendingPathComponent(name), options: .atomic)
        return name
    }

    private static func notifyFinished(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download complete"
        content.body = title
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum Tools {
    static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "\(NSHomeDirectory())/.local/bin",
    ]

    static func path(for name: String) -> String? {
        searchPaths
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Apps launched from the Dock get a minimal PATH; yt-dlp needs to find deno/node and ffmpeg.
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"].map { [$0] } ?? []
        env["PATH"] = (searchPaths + existing).joined(separator: ":")
        return env
    }
}

enum ProcessRunner {
    struct Result: Sendable {
        var status: Int32
        var stderr: String
    }

    static func run(_ process: Process, onLine: @escaping @Sendable (String) async -> Void) async throws -> Result {
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()

        let errReader = Task.detached {
            String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        for try await line in out.fileHandleForReading.bytes.lines {
            await onLine(line)
        }
        let stderr = await errReader.value
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                c.resume()
            }
        }
        return Result(status: process.terminationStatus, stderr: stderr)
    }
}

extension NSImage {
    func jpegData(quality: Double = 0.85) -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
