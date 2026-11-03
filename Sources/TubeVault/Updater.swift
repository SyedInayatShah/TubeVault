import AppKit
import Foundation
import Observation
import SwiftUI
import UserNotifications

/// Checks GitHub for a newer release, tells the user (notification + in-app banner),
/// and installs it in place: download, unzip, swap the app bundle, relaunch.
@MainActor
@Observable
final class Updater {
    struct Release: Equatable {
        var version: String
        var notes: String
        var download: URL
        var page: URL
    }

    enum State: Equatable {
        case idle
        case available(Release)
        case installing(Double)
        case failed(String)
    }

    static let repo = "SyedInayatShah/TubeVault"
    nonisolated static let notificationCategory = "tubevault.update"
    nonisolated static let installAction = "tubevault.update.install"

    var state: State = .idle
    var dismissed = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var notifiedVersion: String? {
        get { UserDefaults.standard.string(forKey: "notifiedUpdateVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "notifiedUpdateVersion") }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The release feed. Overridable (`defaults write com.syedinayatshah.tubevault updateFeedURL …`) for testing.
    private var feed: URL {
        UserDefaults.standard.string(forKey: "updateFeedURL").flatMap(URL.init(string:))
            ?? URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
    }

    var available: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// Checks now and then every few hours while the app stays open.
    func start() {
        let install = UNNotificationAction(identifier: Self.installAction, title: "Update Now")
        let category = UNNotificationCategory(identifier: Self.notificationCategory, actions: [install], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])

        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    /// announce: from "Check for Updates…", so say so when there's nothing new or the check failed.
    func check(announce: Bool = false) async {
        if case .installing = state { return }
        var request = URLRequest(url: feed, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            if announce { Self.tell("Couldn’t check for updates", "Check your internet connection and try again.") }
            return
        }

        let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard Self.isNewer(version, than: Self.currentVersion) else {
            if announce { Self.tell("You’re up to date", "TubeVault \(Self.currentVersion) is the latest version.") }
            return
        }
        if announce { dismissed = false }
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let zip = assets.first(where: { $0["name"] as? String == "TubeVault.zip" }),
              let download = (zip["browser_download_url"] as? String).flatMap(URL.init(string:)) else { return }

        let release = Release(
            version: version,
            notes: json["body"] as? String ?? "",
            download: download,
            page: (json["html_url"] as? String).flatMap(URL.init(string:))
                ?? URL(string: "https://github.com/\(Self.repo)/releases/latest")!
        )
        if available != release { dismissed = false }
        state = .available(release)

        if notifiedVersion != version {
            notifiedVersion = version
            notify(release)
        }
    }

    private func notify(_ release: Release) {
        let content = UNMutableNotificationContent()
        content.title = "TubeVault \(release.version) is available"
        content.body = "Click to update now. TubeVault restarts in a few seconds."
        content.categoryIdentifier = Self.notificationCategory
        let request = UNNotificationRequest(identifier: "update-\(release.version)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Installing

    /// Installs the available release, checking first if none is known yet (e.g. clicked from a notification at launch).
    func install() {
        guard let release = available else {
            Task {
                await check()
                if available != nil { install() }
            }
            return
        }
        state = .installing(0)
        Task {
            do {
                try await install(release)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func install(_ release: Release) async throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("TubeVault-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let zip = work.appendingPathComponent("TubeVault.zip")
        try await download(release.download, to: zip)
        state = .installing(1)

        try await Self.runTool("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let newApp = work.appendingPathComponent("TubeVault.app")
        guard let bundle = Bundle(url: newApp),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError("The download didn’t contain TubeVault.")
        }
        // Gatekeeper would otherwise ask again about the new copy.
        try? await Self.runTool("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw UpdateError("TubeVault can’t replace itself in \(target.deletingLastPathComponent().path).")
        }

        // Once this app has quit: swap in the new copy and open it.
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "$1" && mv "$2" "$1" && open "$1"
        rm -rf "$3"
        """
        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/sh")
        swap.arguments = ["-c", script, "sh", target.path, newApp.path, work.path]
        try swap.run()

        // If downloads are running the app asks first; the swap then happens whenever it does quit.
        NSApp.terminate(nil)
    }

    private func download(_ url: URL, to destination: URL) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("Couldn’t download the update.")
        }
        let total = Double(response.expectedContentLength)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data()
        var received = 0.0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                received += Double(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 { state = .installing(min(received / total, 0.99)) }
            }
        }
        try handle.write(contentsOf: buffer)
    }

    private static func runTool(_ path: String, _ arguments: [String]) async throws {
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
        guard process.terminationStatus == 0 else { throw UpdateError("Couldn’t unpack the update.") }
    }

    private static func tell(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    /// Compares dotted version numbers: "1.10.0" is newer than "1.9.2".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Banner at the top of the window while an update is available or installing.
struct UpdateBanner: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        switch updater.state {
        case .available(let release) where !updater.dismissed:
            bar {
                Image(systemName: "arrow.down.app.fill").foregroundStyle(.tint)
                Text("TubeVault \(release.version) is available").fontWeight(.medium)
                Text("You have \(Updater.currentVersion)").foregroundStyle(.secondary)
                Spacer()
                Button("What’s New") { NSWorkspace.shared.open(release.page) }
                    .buttonStyle(.link)
                Button("Later") { updater.dismissed = true }
                Button("Update Now") { updater.install() }
                    .buttonStyle(.borderedProminent)
            }
        case .installing(let progress):
            bar {
                ProgressView(value: progress).frame(width: 160)
                Text(progress < 1 ? "Downloading update…" : "Installing… TubeVault will restart")
                Spacer()
            }
        case .failed(let message):
            bar {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Update failed: \(message)").lineLimit(1)
                Spacer()
                Button("Try Again") { Task { await updater.check(); updater.install() } }
                Button("Download Manually") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/\(Updater.repo)/releases/latest")!)
                }
            }
        default:
            EmptyView()
        }
    }

    private func bar(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 10, content: content)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
    }
}
