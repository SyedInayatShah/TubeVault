import AppKit
import SwiftUI
import UserNotifications

@main
struct TubeVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("TubeVault", id: "main") {
            ContentView()
                .environment(appDelegate.store)
                .environment(appDelegate.downloads)
                .environment(appDelegate.ui)
                .frame(minWidth: 880, minHeight: 540)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Download from Link…") { appDelegate.ui.showingAddLink = true }
                    .keyboardShortcut("d")
                Button("New Library…") { appDelegate.ui.showingNewLibrary = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Show Downloads Folder") { NSWorkspace.shared.open(Paths.videos) }
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
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = LibraryStore()
    let ui = UIState()
    lazy var downloads = DownloadManager(store: store)

    func applicationWillFinishLaunching(_ notification: Notification) {
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
        NSUpdateDynamicServices()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        store.pruneMissingFiles()
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
        if let link = items.first(where: { $0.name == "url" })?.value {
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
