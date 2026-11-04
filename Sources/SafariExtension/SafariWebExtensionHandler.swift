import AppKit
import SafariServices

/// Safari's side of the extension. Safari sends browser.runtime.sendNativeMessage here (it always goes to
/// the app the extension lives in); each message is relayed to TubeVault's local server, launching the app
/// first if needed. Same messages and replies as the Chrome native host (NativeHost.swift).
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let port = 47823

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]

        DispatchQueue.global(qos: .userInitiated).async {
            let reply = Self.handle(message)
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: reply]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }

    /// Message: {"path": "/download?url=…", "launch": true}
    private static func handle(_ message: [String: Any]) -> [String: Any] {
        guard let path = message["path"] as? String else { return ["error": "missing path"] }
        if let reply = request(path) { return reply }
        guard message["launch"] as? Bool == true else { return ["state": "offline"] }

        launchApp()
        for _ in 0..<60 {
            Thread.sleep(forTimeInterval: 0.25)
            if let reply = request(path) { return reply }
        }
        return ["state": "offline", "error": "TubeVault didn’t start"]
    }

    private static func request(_ path: String) -> [String: Any]? {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.setValue("1", forHTTPHeaderField: "X-TubeVault")

        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: [String: Any]?
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data { result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] }
            done.signal()
        }.resume()
        done.wait()
        return result
    }

    /// Opens TubeVault in the background (it starts its local server on launch). The extension lives in
    /// TubeVault.app/Contents/PlugIns, so the app is three folders up.
    private static func launchApp() {
        let app = Bundle.main.bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: app, configuration: config) { _, _ in done.signal() }
        _ = done.wait(timeout: .now() + 10)
    }
}
