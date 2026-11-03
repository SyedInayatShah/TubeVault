import Foundation

/// Chrome native messaging host. Chrome starts the TubeVault binary with the extension's origin as an
/// argument; each message is relayed to the running app's local server, launching the app first if needed.
/// Native messaging isn't subject to Chrome's local-network restrictions, so this is the reliable path.
enum NativeHost {
    static let name = "com.tubevault.host"
    static let extensionID = "opddfjhogbkolchgdpdjagkfgecdaeof"

    static var isRequested: Bool {
        CommandLine.arguments.dropFirst().contains { $0.hasPrefix("chrome-extension://") }
    }

    // MARK: Host mode

    static func run() -> Never {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        while true {
            let header = input.readData(ofLength: 4)
            guard header.count == 4 else { exit(0) } // Chrome closed the pipe
            let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            let body = input.readData(ofLength: Int(length))
            let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]

            let reply = handle(message)
            let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{}".utf8)
            var size = UInt32(data.count)
            output.write(Data(bytes: &size, count: 4))
            output.write(data)
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
        guard let url = URL(string: "http://127.0.0.1:\(ServerConfig.port)\(path)") else { return nil }
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

    /// Opens TubeVault in the background (it starts its local server on launch).
    private static func launchApp() {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", Bundle.main.bundleURL.path]
        try? open.run()
        open.waitUntilExit()
    }

    // MARK: Registration

    /// Tells Chromium-based browsers where the host is. Re-written on every launch so a moved app keeps working.
    static func installManifests() {
        guard let executable = Bundle.main.executablePath else { return }
        let manifest: [String: Any] = [
            "name": name,
            "description": "TubeVault",
            "path": executable,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes]) else { return }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let browsers = [
            "Google/Chrome", "Google/Chrome Beta", "Google/Chrome Dev", "Google/Chrome Canary",
            "Google/Chrome for Testing", "Chromium", "BraveSoftware/Brave-Browser",
            "Microsoft Edge", "Vivaldi", "Arc/User Data",
        ]
        for browser in browsers {
            let base = support.appendingPathComponent(browser, isDirectory: true)
            guard FileManager.default.fileExists(atPath: base.path) else { continue }
            let dir = base.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: dir.appendingPathComponent("\(name).json"), options: .atomic)
        }
    }
}

enum ServerConfig {
    static let port: UInt16 = 47823
}
