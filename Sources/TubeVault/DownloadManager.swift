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
    @ObservationIgnored var started = false
    @ObservationIgnored var parts = 1
    @ObservationIgnored var partIndex = 0
    @ObservationIgnored var lastFraction = 0.0
    @ObservationIgnored var outputPath: String?
    @ObservationIgnored var height: Int?
    @ObservationIgnored var width: Int?
    @ObservationIgnored var thumbnailJob: Task<String?, Never>?
    /// The library (a saved playlist) the video goes into once it's downloaded.
    @ObservationIgnored var libraryID: UUID?
    /// Part of "Save all" from the Shorts feed: no notification per Short.
    @ObservationIgnored var batch = false
    /// When it was queued; saved Shorts keep this order so the feed plays like YouTube's.
    let queuedAt = Date()

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
        height = nil
        width = nil
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

    /// into: the library (a saved playlist) to put the video in. quiet: no toast, for a batch.
    func enqueue(_ raw: String, into libraryID: UUID? = nil, quiet: Bool = false, batch: Bool = false) {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: link),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            notice = "That doesn’t look like a video link."
            return
        }
        if let id = Self.youtubeID(from: url), store.contains(videoID: id) {
            if let libraryID { store.move(videoID: id, to: libraryID) }
            if !quiet { notice = "Already in your library." }
            return
        }
        if let existing = tasks.first(where: { $0.url == link && !$0.isFailed }) {
            if let libraryID { existing.libraryID = libraryID }
            if !quiet { notice = "Already downloading." }
            return
        }
        let task = DownloadTask(url: link)
        task.libraryID = libraryID
        task.batch = batch
        tasks.append(task)
        if !quiet { notice = "Download started." }
        startQueued()
    }

    func task(forVideo id: String) -> DownloadTask? {
        tasks.first { $0.videoID == id || URL(string: $0.url).flatMap(Self.youtubeID(from:)) == id }
    }

    /// Keeps the Mac from idle-sleeping while anything downloads, so a long "Save all" carries on.
    @ObservationIgnored private var awake: NSObjectProtocol?

    private func keepAwake() {
        if running > 0, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated], reason: "Downloading videos")
        } else if running == 0, let awake {
            ProcessInfo.processInfo.endActivity(awake)
            self.awake = nil
        }
    }

    // MARK: Save all Shorts

    /// "Save all" on YouTube Shorts: the page feeds in the upcoming Shorts a few at a time (add),
    /// and reads back how the ones it sent (ids) are doing. cancel: Shorts to drop if not started yet.
    func shortsBatch(add: [String], ids: [String], cancel: [String]) -> [String: Any] {
        var cancelled: [String] = []
        for id in cancel {
            if let task = task(forVideo: id), !task.started {
                self.cancel(task)
                cancelled.append(id)
            }
        }
        let free = (try? Paths.support.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? .max
        let full = free < 2_000_000_000
        if !full {
            for id in add { enqueue("https://www.youtube.com/shorts/\(id)", quiet: true, batch: true) }
        }
        var saved = 0, pending = 0, failed = 0
        for id in ids where !cancelled.contains(id) {
            if store.contains(videoID: id) { saved += 1 }
            else if let task = task(forVideo: id) { if task.isFailed { failed += 1 } else { pending += 1 } }
            else { failed += 1 }
        }
        var reply: [String: Any] = ["saved": saved, "pending": pending, "failed": failed, "full": full,
                                    "cancelled": cancelled]
        if let current = tasks.first(where: { $0.batch && $0.state == .downloading && $0.title != $0.url }) {
            reply["current"] = current.title
        }
        return reply
    }

    // MARK: Playlists

    struct PlaylistEntry {
        var id: String
        var title: String
        var channel: String
        var duration: Double?
    }

    enum PlaylistFetch {
        case loading
        case ready(title: String, entries: [PlaylistEntry], fetched: Date)
        case failed(String)
    }

    @ObservationIgnored private var playlistFetches: [String: PlaylistFetch] = [:]

    /// The playlist's videos for the picker on YouTube. Fetching takes a few seconds, so the first call
    /// starts it and answers "loading"; the extension asks again until it's ready.
    /// video: the video it's playing on, which Mixes need.
    func playlist(_ listID: String, video: String?) -> [String: Any] {
        switch playlistFetches[listID] {
        case .ready(let title, let entries, let fetched) where Date().timeIntervalSince(fetched) < 300:
            return [
                "state": "ready",
                "title": title,
                "entries": entries.map { e in
                    var item: [String: Any] = ["id": e.id, "title": e.title, "channel": e.channel,
                                               "saved": store.contains(videoID: e.id)]
                    if let d = e.duration { item["duration"] = d }
                    return item
                },
            ]
        case .loading:
            return ["state": "loading"]
        case .failed(let message):
            playlistFetches[listID] = nil // the next request tries again
            return ["state": "failed", "error": message]
        default:
            playlistFetches[listID] = .loading
            Task { playlistFetches[listID] = await Self.fetchPlaylist(listID, video: video) }
            return ["state": "loading"]
        }
    }

    nonisolated private static func fetchPlaylist(_ listID: String, video: String?) async -> PlaylistFetch {
        guard let ytdlp = Tools.path(for: "yt-dlp") else {
            return .failed("yt-dlp isn’t installed. In Terminal run: brew install yt-dlp ffmpeg")
        }
        let url = video.map { "https://www.youtube.com/watch?v=\($0)&list=\(listID)" }
            ?? "https://www.youtube.com/playlist?list=\(listID)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.arguments = ["--flat-playlist", "--yes-playlist", "-J", "--no-warnings", url]
        process.environment = Tools.environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return .failed(error.localizedDescription) }

        let errReader = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
        let data = await Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
        let stderr = String(decoding: await errReader.value, as: UTF8.self)
        process.waitUntilExit()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["entries"] as? [[String: Any]] else {
            return .failed(errorMessage(from: stderr))
        }
        let entries = raw.compactMap { e -> PlaylistEntry? in
            guard let id = e["id"] as? String, let title = e["title"] as? String,
                  !["[Private video]", "[Deleted video]"].contains(title) else { return nil }
            return PlaylistEntry(id: id, title: title,
                                 channel: (e["channel"] ?? e["uploader"]) as? String ?? "",
                                 duration: e["duration"] as? Double)
        }
        return .ready(title: json["title"] as? String ?? "YouTube Playlist", entries: entries, fetched: Date())
    }

    /// Downloads the picked videos, in the picked order, into the playlist's own library.
    func downloadPlaylist(_ listID: String, title: String, ids: [String]) -> [String: Any] {
        let library = store.playlistLibrary(listID, title: title, order: ids)
        for id in ids {
            enqueue("https://www.youtube.com/watch?v=\(id)", into: library.id, quiet: true)
        }
        notice = "Downloading \(ids.count) video\(ids.count == 1 ? "" : "s") into “\(library.name)”."
        return playlistStatus(listID)
    }

    /// Overall progress of a saved playlist, for the bar on YouTube.
    func playlistStatus(_ listID: String) -> [String: Any] {
        guard let library = store.library(forPlaylist: listID), let order = library.order else {
            return ["state": "none"]
        }
        let missing = order.filter { !store.contains(videoID: $0) }
        let pending = missing.compactMap { task(forVideo: $0) }.filter { !$0.isFailed }
        let failed = missing.count - pending.count
        let current = pending.first { $0.state != .starting } ?? pending.first
        let saved = order.count - missing.count
        let progress = (Double(saved) + pending.map(\.progress).reduce(0, +)) / Double(max(order.count, 1))
        var reply: [String: Any] = [
            "state": missing.isEmpty ? "done" : pending.isEmpty ? "failed" : "downloading",
            "title": library.name,
            "total": order.count,
            "saved": saved,
            "failed": failed,
            "progress": progress,
        ]
        // Until yt-dlp reports the title, the task's title is just its link.
        if let current, current.title != current.url { reply["current"] = current.title }
        return reply
    }

    /// Tries the playlist's failed videos again.
    func retryPlaylist(_ listID: String) -> [String: Any] {
        guard let library = store.library(forPlaylist: listID), let order = library.order else {
            return ["state": "none"]
        }
        for id in order where !store.contains(videoID: id) {
            if let task = task(forVideo: id) {
                if task.isFailed { retry(task) }
            } else {
                enqueue("https://www.youtube.com/watch?v=\(id)", into: library.id, quiet: true)
            }
        }
        return playlistStatus(listID)
    }

    /// YouTube rate-limits (and serves low quality to) many simultaneous downloads, so a few run at once.
    private static let maxConcurrent = 3
    @ObservationIgnored private var running = 0

    private func startQueued() {
        for task in tasks where !task.started && !task.cancelled {
            guard running < Self.maxConcurrent else { return }
            task.started = true
            running += 1
            keepAwake()
            Task {
                await run(task)
                running -= 1
                keepAwake()
                startQueued()
            }
        }
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
        task.started = false
        startQueued()
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

    /// retried: a second attempt after YouTube blocked or throttled the first.
    /// cookiesFrom: a browser to borrow the YouTube sign-in from, used when YouTube asks to "confirm you're not a bot".
    private func run(_ task: DownloadTask, retried: Bool = false, cookiesFrom browser: String? = nil) async {
        guard let ytdlp = Tools.path(for: "yt-dlp") else {
            task.state = .failed("yt-dlp isn’t installed. In Terminal run: brew install yt-dlp ffmpeg")
            return
        }
        Paths.ensure()

        var args = [
            "--no-playlist",
            "--quiet", "--progress", "--newline", "--no-colors",
            // Best quality available: highest resolution, then frame rate, then the better codec (VP9 over H.264).
            // AV1 is skipped (Macs before M3 can't decode it) and so is HDR, which looks washed out in AVKit.
            "-f", "bv*[vcodec!^=av01][dynamic_range=SDR]+ba[ext=m4a]/bv*[vcodec!^=av01]+ba/b",
            "-S", "res,fps,vcodec,acodec:m4a",
            "--merge-output-format", "mp4",
            "--progress-template",
            "download:TVP %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s %(progress.speed)s %(progress.eta)s",
            "--print", "before_dl:TVINFO %(.{id,title,channel,uploader,duration,thumbnail,height,width})j",
            "--print", "before_dl:TVPARTS %(requested_formats.:.format_id)j",
            "--print", "after_move:TVFILE %(filepath)s",
            "-o", Paths.videos.path + "/%(title).80B [%(id)s].%(ext)s",
            // When YouTube bot-checks the default clients, the embedded player still offers full quality
            // and the mobile web client at least a 360p fallback.
            "--extractor-args", "youtube:player_client=default,web_embedded,mweb",
        ]
        if let browser {
            args += ["--cookies-from-browser", browser]
        }
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
            let message = Self.errorMessage(from: result.stderr)
            if !retried, message.contains("not a bot"), let signedIn = Tools.cookieBrowser {
                // Retry once as the user's signed-in browser (macOS may ask to allow Keychain access).
                task.reset()
                return await run(task, retried: true, cookiesFrom: signedIn)
            }
            task.state = .failed(message)
            return
        }
        // Only a low-quality copy got past YouTube's bot check or rate limit: wait a moment and fetch it again,
        // as the signed-in browser if YouTube asked for that.
        let blocked = ["not a bot", "429", "PO Token"].contains { result.stderr.contains($0) }
        if !retried, (task.height ?? .max) < 720, blocked {
            try? FileManager.default.removeItem(atPath: path)
            task.reset()
            try? await Task.sleep(for: .seconds(8))
            if task.cancelled { return }
            let signIn = result.stderr.contains("not a bot") ? Tools.cookieBrowser : nil
            return await run(task, retried: true, cookiesFrom: signIn)
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
        task.height = obj["height"] as? Int
        task.width = obj["width"] as? Int
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
            libraryID: task.libraryID,
            addedAt: task.queuedAt,
            fileSize: size,
            isShort: Self.isShort(task),
            queuedAt: task.queuedAt.timeIntervalSince1970
        ))
        if let seconds = pendingPositions.removeValue(forKey: id) {
            store.setPosition(videoID: id, seconds: seconds)
        }
        tasks.removeAll { $0.id == task.id }
        // A playlist gets one notification, once all of it is saved.
        if let library = store.library(task.libraryID), library.isPlaylist {
            let order = library.order ?? []
            if order.allSatisfy(store.contains(videoID:)) {
                Self.notifyFinished(title: "“\(library.name)” is saved: \(order.count) video\(order.count == 1 ? "" : "s")")
            }
        } else {
            if !task.batch { Self.notifyFinished(title: task.title) }
        }
    }

    // MARK: Helpers

    /// A /shorts/ link, or a vertical video of three minutes or less.
    private static func isShort(_ task: DownloadTask) -> Bool {
        if task.url.contains("/shorts/") { return true }
        guard let w = task.width, let h = task.height else { return false }
        return h > w && (task.duration ?? .infinity) <= 180
    }

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

    nonisolated private static func errorMessage(from stderr: String) -> String {
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

    /// The first installed browser yt-dlp can read YouTube cookies from.
    static var cookieBrowser: String? {
        let apps = [
            ("chrome", "Google Chrome"), ("brave", "Brave Browser"), ("edge", "Microsoft Edge"),
            ("chromium", "Chromium"), ("vivaldi", "Vivaldi"), ("firefox", "Firefox"), ("safari", "Safari"),
        ]
        return apps.first { FileManager.default.fileExists(atPath: "/Applications/\($0.1).app") }?.0
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
