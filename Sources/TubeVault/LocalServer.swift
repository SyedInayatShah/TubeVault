import Foundation
import Network

/// Tiny HTTP server on 127.0.0.1 so the browser extension can start downloads and read progress.
/// Only requests carrying the `X-TubeVault` header (which web pages can't send cross-origin) are accepted.
@MainActor
final class LocalServer {
    static let port: UInt16 = 47823

    private let downloads: DownloadManager
    private let store: LibraryStore
    private var listener: NWListener?

    init(downloads: DownloadManager, store: LibraryStore) {
        self.downloads = downloads
        self.store = store
    }

    func start() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { return connection.cancel() }
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                let (status, body) = self.respond(to: request)
                self.send(status: status, json: body, on: connection)
            }
        }
    }

    private func respond(to request: String) -> (String, [String: Any]) {
        let lines = request.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return ("400 Bad Request", ["error": "bad request"]) }

        let headers = lines.dropFirst().map { $0.lowercased() }
        guard headers.contains(where: { $0.hasPrefix("x-tubevault:") }) else {
            return ("403 Forbidden", ["error": "forbidden"])
        }
        if let origin = headers.first(where: { $0.hasPrefix("origin:") }),
           !origin.contains("chrome-extension://") {
            return ("403 Forbidden", ["error": "forbidden"])
        }

        guard let components = URLComponents(string: "http://localhost" + parts[1]) else {
            return ("400 Bad Request", ["error": "bad url"])
        }
        let query = Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { a, _ in a }
        )

        switch components.path {
        case "/ping":
            return ("200 OK", ["ok": true])
        case "/download":
            guard let link = query["url"] else { return ("400 Bad Request", ["error": "missing url"]) }
            downloads.enqueue(link)
            return ("200 OK", status(for: query["v"] ?? DownloadManager.youtubeID(from: URL(string: link)!) ?? ""))
        case "/status":
            return ("200 OK", status(for: query["v"] ?? ""))
        default:
            return ("404 Not Found", ["error": "not found"])
        }
    }

    private func status(for videoID: String) -> [String: Any] {
        guard !videoID.isEmpty else { return ["state": "none"] }
        if store.contains(videoID: videoID) {
            return ["state": "done", "progress": 1]
        }
        let task = downloads.tasks.first {
            $0.videoID == videoID ||
                URL(string: $0.url).flatMap(DownloadManager.youtubeID(from:)) == videoID
        }
        guard let task else { return ["state": "none"] }
        switch task.state {
        case .starting: return ["state": "starting", "progress": 0]
        case .downloading: return ["state": "downloading", "progress": task.progress]
        case .finishing: return ["state": "finishing", "progress": 1]
        case .failed(let message): return ["state": "failed", "error": message]
        }
    }

    private func send(status: String, json: [String: Any], on connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
