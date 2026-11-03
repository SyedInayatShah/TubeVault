import AppKit
import SwiftUI
import UserNotifications
import VideoToolbox

/// Chrome runs this same binary as its native messaging host; otherwise start the app normally.
@main
enum Launcher {
    static func main() {
        if NativeHost.isRequested { NativeHost.run() }
        TubeVaultApp.main()
    }
}

struct TubeVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("TubeVault", id: "main") {
            ContentView()
                .environment(appDelegate.store)
                .environment(appDelegate.downloads)
                .environment(appDelegate.ui)
                .environment(appDelegate.updater)
                .frame(minWidth: 880, minHeight: 540)
        }
        .defaultSize(width: 1120, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Download from Link…") { appDelegate.ui.showingAddLink = true }
                    .keyboardShortcut("d")
                Button("New Library…") { appDelegate.ui.showingNewLibrary = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Delete Videos…") { appDelegate.ui.bulkDelete = .all }
                Button("Delete Shorts…") { appDelegate.ui.bulkDelete = .shorts }
            }
            CommandGroup(after: .sidebar) {
                Button("Show Video Files in Finder") { NSWorkspace.shared.open(Paths.videos) }
            }
            CommandGroup(replacing: .help) {
                Button("TubeVault Setup Guide") { appDelegate.ui.showingSetup = true }
                Button("Check for Updates…") { Task { await appDelegate.updater.check(announce: true) } }
                Button("TubeVault on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/SyedInayatShah/TubeVault")!)
                }
            }
        }
    }
}

/// Window-level UI state that menu commands can also toggle.
@MainActor
@Observable
final class UIState {
    var showingAddLink = false
    var showingNewLibrary = false
    var showingSetup = !UserDefaults.standard.bool(forKey: "hasSeenSetup")
    /// Set to show a video in the player at its saved position.
    var openVideoID: String?
    /// The video handed over from a pause on YouTube: it opens paused instead of playing on.
    var openPaused: String?
    /// The Short to show in the Shorts feed.
    var currentShort: String?
    /// Shows the pick-and-delete sheet for All Videos or Shorts.
    var bulkDelete: SidebarItem?
    /// A saved playlist to show, from "Open in TubeVault" on YouTube.
    var openLibrary: UUID?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = LibraryStore()
    let ui = UIState()
    let updater = Updater()
    lazy var downloads = DownloadManager(store: store)
    private lazy var server = LocalServer(downloads: downloads, store: store)

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Full-quality YouTube downloads are VP9; AVKit plays them once the system decoder is enabled.
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
        server.start()
        // Set before launch finishes so a click on an update notification that launched us is delivered.
        UNUserNotificationCenter.current().delegate = self

        // Handles tubevault://download?url=… links sent by the browser extension.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NativeHost.installManifests()
        ChromeExtension.refreshIfOutdated()
        NSUpdateDynamicServices()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        updater.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        store.pruneMissingFiles()
        // Paused a downloaded video on YouTube? Pick up right there.
        if let id = downloads.resumeRequest, store.contains(videoID: id) {
            downloads.resumeRequest = nil
            ui.openPaused = id
            ui.openVideoID = id
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keep downloading in the background
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let active = downloads.activeTasks.count
        guard active > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit while downloading?"
        alert.informativeText = "\(active) download\(active == 1 ? " is" : "s are") still in progress and will be cancelled."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Keep Downloading")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        downloads.cancelAll()
        return .terminateNow
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        handleIncoming(url)
    }

    private func handleIncoming(_ url: URL) {
        guard url.scheme == "tubevault" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first(where: { $0.name == name })?.value }

        if url.host == "open", let list = value("list") {
            // tubevault://open?list=<playlist id> once a playlist is saved.
            guard let library = store.library(forPlaylist: list) else { return }
            ui.showingSetup = false
            ui.openLibrary = library.id
            NSApp.activate(ignoringOtherApps: true)
        } else if url.host == "open" {
            // tubevault://open?v=<id>&t=<seconds> from the "Open TubeVault" button on YouTube.
            guard let id = value("v"), store.contains(videoID: id) else { return }
            if let t = value("t").flatMap(Double.init) {
                store.setPosition(videoID: id, seconds: t)
            }
            downloads.resumeRequest = nil
            ui.openPaused = id
            ui.openVideoID = id
            NSApp.activate(ignoringOtherApps: true)
        } else if let link = value("url") {
            downloads.enqueue(link)
        }
    }

    /// macOS Services menu: right-click a link in Safari (or any app) → Services → Download with TubeVault.
    @objc func downloadVideo(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let link = pboard.string(forType: .URL)
            ?? pboard.string(forType: NSPasteboard.PasteboardType("public.url"))
            ?? pboard.string(forType: .string)
        if let link {
            downloads.enqueue(link)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.categoryIdentifier == Updater.notificationCategory,
              response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        await MainActor.run { updater.install() }
    }
}
