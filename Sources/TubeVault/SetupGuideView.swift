import AppKit
import SwiftUI

/// In-app walkthrough: install yt-dlp, add the Chrome extension, and get past Gatekeeper.
struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenSetup") private var hasSeenSetup = false

    @State private var ytdlpPath = Tools.path(for: "yt-dlp")
    @State private var ffmpegPath = Tools.path(for: "ffmpeg")
    @State private var extensionFolder: URL?

    private let brewCommand = "brew install yt-dlp ffmpeg deno"
    private let quarantineCommand = "xattr -dr com.apple.quarantine /Applications/TubeVault.app"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    engineSection
                    chromeSection
                    safariSection
                    gatekeeperSection
                }
                .padding(28)
            }
            Divider()
            HStack {
                Text("You can reopen this any time from Help › TubeVault Setup Guide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    hasSeenSetup = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 640, height: 520)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to TubeVault").font(.title.weight(.bold))
                Text("Three quick steps and you can right-click any YouTube video to keep it for offline viewing.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var engineSection: some View {
        GuideCard(number: 1, title: "Install the download engine", symbol: "shippingbox") {
            Text("TubeVault uses the free tools **yt-dlp** and **ffmpeg** to download videos. Install them once with [Homebrew](https://brew.sh) by pasting this into Terminal:")
            CommandBox(command: brewCommand)
            HStack(spacing: 14) {
                StatusPill(name: "yt-dlp", ok: ytdlpPath != nil)
                StatusPill(name: "ffmpeg", ok: ffmpegPath != nil)
                Spacer()
                Button("Open Terminal") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
                Button("Check Again") {
                    ytdlpPath = Tools.path(for: "yt-dlp")
                    ffmpegPath = Tools.path(for: "ffmpeg")
                }
            }
        }
    }

    private var chromeSection: some View {
        GuideCard(number: 2, title: "Add “Download with TubeVault” to Chrome", symbol: "cursorarrow.click.2") {
            StepRow(n: 1, text: "Save the extension to your Documents folder.") {
                Button(extensionFolder == nil ? "Save Extension" : "Saved ✓") {
                    extensionFolder = ChromeExtension.install()
                }
            }
            StepRow(n: 2, text: "Open Chrome’s Extensions page (or type **chrome://extensions** in the address bar).") {
                Button("Open in Chrome") { ChromeExtension.openExtensionsPage() }
            }
            StepRow(n: 3, text: "Turn on **Developer mode** with the switch in the **top-right corner** of that page. New buttons appear on the left.")
            StepRow(n: 4, text: "Click **Load unpacked**, go to **Documents**, select the **TubeVault Chrome Extension** folder and click **Select**.")
            StepRow(n: 5, text: "Open any YouTube video and click the **⬇ download icon** in the player’s bottom bar, next to the settings ⚙ icon. A red progress bar shows next to it. When it’s saved, the button becomes **Open TubeVault**. Click it to watch here, paused at the same spot.")
            Label("Already had an older TubeVault extension? Remove its card in chrome://extensions first, then load the new folder. After future updates, click Save Extension again and the ↻ reload arrow on the card.", systemImage: "lightbulb")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var safariSection: some View {
        GuideCard(number: 3, title: "Using Safari?", symbol: "safari") {
            Text("Safari uses the same extension folder as Chrome, with the same buttons.")
            StepRow(n: 1, text: "Save the extension to your Documents folder (step 2.1 above).")
            StepRow(n: 2, text: "In Safari, open **Settings › Advanced** and turn on **Show features for web developers**.")
            StepRow(n: 3, text: "Open **Settings › Developer**, click **Add Temporary Extension…** and choose **Documents › TubeVault Chrome Extension**.")
            StepRow(n: 4, text: "On YouTube, click the TubeVault icon next to the address bar, choose **Always Allow on This Website**, and refresh.")
            Label("Safari removes temporary extensions when it quits, so repeat step 3 after restarting Safari. Keep TubeVault open while you download from Safari.", systemImage: "lightbulb")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Another browser? Right-click a YouTube link and choose **Services › Download with TubeVault**, or press **⌘D** in TubeVault and paste the link.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var gatekeeperSection: some View {
        GuideCard(number: nil, title: "If macOS says TubeVault can’t be opened", symbol: "lock.shield") {
            Text("TubeVault isn’t from the App Store, so the first time you open it macOS may say *“Apple could not verify TubeVault”* or *“TubeVault is damaged”*. It’s safe. To allow it:")
            StepRow(n: 1, text: "Click **Done** (not Move to Trash) on the warning.")
            StepRow(n: 2, text: "Open **System Settings › Privacy & Security** and scroll down to **Security**.") {
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            StepRow(n: 3, text: "Next to *“TubeVault was blocked”*, click **Open Anyway** and enter your password.")
            Text("Still blocked, or it says “damaged”? Paste this into Terminal, then open TubeVault again:")
                .padding(.top, 4)
            CommandBox(command: quarantineCommand)
        }
    }
}

// MARK: - Building blocks

private struct GuideCard<Content: View>: View {
    let number: Int?
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(number == nil ? Color.orange : Color.red, in: RoundedRectangle(cornerRadius: 8))
                Text(number.map { "Step \($0) · \(title)" } ?? title)
                    .font(.headline)
            }
            content
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StepRow<Accessory: View>: View {
    let n: Int
    let text: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(.quaternary, in: Circle())
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
    }
}

extension StepRow where Accessory == EmptyView {
    init(n: Int, text: LocalizedStringKey) {
        self.init(n: n, text: text) { EmptyView() }
    }
}

private struct CommandBox: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusPill: View {
    let name: String
    let ok: Bool

    var body: some View {
        Label(ok ? "\(name) installed" : "\(name) missing",
              systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(ok ? .green : .orange)
    }
}

enum ChromeExtension {
    static let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TubeVault Chrome Extension", isDirectory: true)

    /// Copies the extension bundled inside the app to ~/Documents/TubeVault Chrome Extension.
    @discardableResult
    static func install() -> URL? {
        guard let source = Bundle.main.url(forResource: "ChromeExtension", withExtension: nil) else { return nil }
        let fm = FileManager.default
        Paths.ensure()
        try? fm.removeItem(at: folder)
        do {
            try fm.copyItem(at: source, to: folder)
        } catch {
            return nil
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
        return folder
    }

    /// After an app update, refreshes a previously saved extension folder with the bundled (newer) one.
    /// Chrome picks up the new files when it restarts or when the extension is reloaded.
    static func refreshIfOutdated() {
        guard let source = Bundle.main.url(forResource: "ChromeExtension", withExtension: nil),
              FileManager.default.fileExists(atPath: folder.path),
              version(at: folder) != version(at: source) else { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        for item in items {
            let target = folder.appendingPathComponent(item.lastPathComponent)
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: item, to: target)
        }
    }

    private static func version(at folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }

    static func openExtensionsPage() {
        let page = URL(string: "chrome://extensions")!
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            NSWorkspace.shared.open([page], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(page.absoluteString, forType: .string)
        }
    }
}
