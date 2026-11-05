import Foundation
import Observation
import Security

/// Sets up the download engine (yt-dlp, deno, ffmpeg) by itself, so nobody needs Homebrew or Terminal.
/// Each tool comes from its official release and is checked (checksum or Apple Developer ID signature)
/// before it's used. Tools already installed with Homebrew are used as they are.
@MainActor
@Observable
final class ToolInstaller {
    enum State: Equatable {
        case idle
        case installing(Double)
        case ready
        case failed(String)
    }

    static let shared = ToolInstaller()
    static let folder = Paths.support.appendingPathComponent("Tools", isDirectory: true)

    var state: State = .idle

    @ObservationIgnored private var job: Task<Void, Never>?

    private struct Tool: Sendable {
        enum Check: Sendable {
            /// SHA-256 listed in a checksum file next to the download.
            case checksum(URL)
            /// Signed with this Apple Developer ID team.
            case team(String)
        }

        var name: String
        var url: URL
        var zipped: Bool
        var check: Check
        var size: Double // rough MB, for the progress bar
    }

    private static var tools: [Tool] {
        #if arch(arm64)
        let deno = "deno-aarch64-apple-darwin.zip", ffmpegArch = "arm64"
        #else
        let deno = "deno-x86_64-apple-darwin.zip", ffmpegArch = "amd64"
        #endif
        let ytdlp = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/"
        let denoBase = "https://github.com/denoland/deno/releases/latest/download/"
        let ffmpeg = "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(ffmpegArch)/release/"
        return [
            Tool(name: "yt-dlp", url: URL(string: ytdlp + "yt-dlp_macos")!, zipped: false,
                 check: .checksum(URL(string: ytdlp + "SHA2-256SUMS")!), size: 37),
            Tool(name: "deno", url: URL(string: denoBase + deno)!, zipped: true,
                 check: .checksum(URL(string: denoBase + deno + ".sha256sum")!), size: 39),
            Tool(name: "ffmpeg", url: URL(string: ffmpeg + "ffmpeg.zip")!, zipped: true,
                 check: .team("KU3N25YGLU"), size: 28),
            Tool(name: "ffprobe", url: URL(string: ffmpeg + "ffprobe.zip")!, zipped: true,
                 check: .team("KU3N25YGLU"), size: 28),
        ]
    }

    /// The tools that aren't installed anywhere yet.
    private static var missing: [Tool] {
        tools.filter { Tools.path(for: $0.name) == nil }
    }

    var isReady: Bool { Self.missing.isEmpty }

    var failureMessage: String {
        if case .failed(let message) = state { return message }
        return "The download engine isn’t set up. Open Help › TubeVault Setup Guide and click Set Up."
    }

    /// Installs whatever is missing. Safe to call any number of times: callers share one install.
    func ensure() async {
        if job == nil {
            if isReady {
                state = .ready
                return
            }
            job = Task { await install() }
        }
        await job?.value
        job = nil
    }

    /// YouTube often breaks older yt-dlp versions, so TubeVault's own copy is swapped for the latest
    /// release when it changes. Checked at most once a day; a Homebrew copy is left to Homebrew.
    func refreshYtDlp() async {
        let key = "ytdlpCheckedAt"
        let last = UserDefaults.standard.double(forKey: key)
        guard job == nil, Date().timeIntervalSince1970 - last > 24 * 3600,
              let tool = Self.tools.first(where: { $0.name == "yt-dlp" }), case .checksum(let list) = tool.check
        else { return }
        let ours = Self.folder.appendingPathComponent(tool.name)
        guard FileManager.default.fileExists(atPath: ours.path),
              let sums = try? await URLSession.shared.data(from: list).0,
              let latest = Self.hash(named: tool.url.lastPathComponent, in: String(decoding: sums, as: UTF8.self))
        else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        guard (try? Self.sha256(of: ours)) != latest else { return }
        try? await install(tool) { _ in }
    }

    private func install() async {
        let todo = Self.missing
        let total = todo.reduce(0) { $0 + $1.size }
        var done = 0.0
        state = .installing(0)
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            for tool in todo {
                let before = done
                try await install(tool) { fraction in
                    Task { @MainActor in
                        if case .installing = self.state {
                            self.state = .installing(min((before + fraction * tool.size) / total, 0.99))
                        }
                    }
                }
                done += tool.size
            }
            state = .ready
        } catch {
            state = .failed((error as? InstallError)?.message ?? "Couldn’t set up the download engine. Check your internet connection and try again.")
        }
    }

    private func install(_ tool: Tool, progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("TubeVault-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let download = work.appendingPathComponent(tool.url.lastPathComponent)
        try await Self.download(tool.url, to: download, progress: progress)

        if case .checksum(let list) = tool.check {
            guard let sums = try? await URLSession.shared.data(from: list).0,
                  let expected = Self.hash(named: tool.url.lastPathComponent, in: String(decoding: sums, as: UTF8.self)),
                  expected == (try Self.sha256(of: download))
            else { throw InstallError("\(tool.name) didn’t match its official checksum, so it wasn’t installed.") }
        }

        var binary = download
        if tool.zipped {
            try await Self.run("/usr/bin/ditto", ["-x", "-k", download.path, work.path])
            binary = work.appendingPathComponent(tool.name)
        }
        guard fm.fileExists(atPath: binary.path) else {
            throw InstallError("Couldn’t unpack \(tool.name).")
        }
        if case .team(let team) = tool.check, !Self.isSigned(binary, byTeam: team) {
            throw InstallError("\(tool.name) isn’t signed by its developer, so it wasn’t installed.")
        }

        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let destination = Self.folder.appendingPathComponent(tool.name)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: binary, to: destination)
    }

    // MARK: Helpers

    nonisolated private static func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw InstallError("Couldn’t download \(url.lastPathComponent).")
        }
        let total = Double(response.expectedContentLength)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data()
        var received = 0.0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 18 {
                try handle.write(contentsOf: buffer)
                received += Double(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 { progress(received / total) }
            }
        }
        try handle.write(contentsOf: buffer)
    }

    /// Finds "<hash>  <name>" in a checksum list.
    nonisolated private static func hash(named name: String, in list: String) -> String? {
        for line in list.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts.last.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "*")) }) == name {
                return parts[0].lowercased()
            }
        }
        return nil
    }

    nonisolated private static func sha256(of file: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", file.path]
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: " ").first.map { String($0).lowercased() } ?? ""
    }

    /// True when the file carries a valid Apple Developer ID signature from this team.
    nonisolated private static func isSigned(_ file: URL, byTeam team: String) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        guard SecStaticCodeCreateWithPath(file as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }

    private static func run(_ path: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                c.resume()
            }
        }
        guard process.terminationStatus == 0 else { throw InstallError("Couldn’t unpack a download.") }
    }

    struct InstallError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
