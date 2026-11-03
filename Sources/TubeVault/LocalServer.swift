import Foundation
import Network

/// Tiny HTTP server on 127.0.0.1 so the browser extension can start downloads and read progress.
/// Only requests carrying the `X-TubeVault` header (which web pages can't send cross-origin) are accepted.
@MainActor
final class LocalServer {
    static let port = ServerConfig.port

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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { return connection.cancel() }
                self.handle(String(decoding: data ?? Data(), as: UTF8.self), on: connection)
            }
        }
    }

    private func handle(_ request: String, on connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        // Only the browser extension may talk to us; plain tools like curl send no Origin.
        let origin = headers["origin"]
        if let origin, !origin.hasPrefix("chrome-extension://") {
            return send(status: "403 Forbidden", json: ["error": "forbidden"], origin: nil, on: connection)
        }

        // Chrome's CORS / Local Network Access preflight for the custom header.
        if parts.first == "OPTIONS" {
            return send(status: "204 No Content", json: nil, origin: origin, on: connection)
        }

        let (status, body) = respond(method: parts, headers: headers)
        send(status: status, json: body, origin: origin, on: connection)
    }

    private func respond(method parts: [Substring], headers: [String: String]) -> (String, [String: Any]) {
        guard parts.count >= 2 else { return ("400 Bad Request", ["error": "bad request"]) }
        guard headers["x-tubevault"] != nil else {
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
        case "/position":
            guard let id = query["v"], !id.isEmpty, let seconds = Double(query["t"] ?? "") else {
                return ("400 Bad Request", ["error": "missing v or t"])
            }
            downloads.recordPosition(videoID: id, seconds: seconds)
            return ("200 OK", ["ok": true])
        case "/playlist":
            guard let list = query["list"], !list.isEmpty else { return ("400 Bad Request", ["error": "missing list"]) }
            return ("200 OK", downloads.playlist(list, video: query["v"].flatMap { $0.isEmpty ? nil : $0 }))
        case "/playlist-download":
            let ids = (query["ids"] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
            guard let list = query["list"], !list.isEmpty, !ids.isEmpty else {
                return ("400 Bad Request", ["error": "missing list or ids"])
            }
            return ("200 OK", downloads.downloadPlaylist(list, title: query["title"] ?? "", ids: ids))
        case "/playlist-status":
            return ("200 OK", downloads.playlistStatus(query["list"] ?? ""))
        case "/playlist-retry":
            return ("200 OK", downloads.retryPlaylist(query["list"] ?? ""))
        default:
            return ("404 Not Found", ["error": "not found"])
        }
    }

    private func status(for videoID: String) -> [String: Any] {
        guard !videoID.isEmpty else { return ["state": "none"] }
        if store.contains(videoID: videoID) {
            return ["state": "done", "progress": 1]
        }
        guard let task = downloads.task(forVideo: videoID) else { return ["state": "none"] }
        switch task.state {
        case .starting: return ["state": "starting", "progress": 0]
        case .downloading: return ["state": "downloading", "progress": task.progress]
        case .finishing: return ["state": "finishing", "progress": 1]
        case .failed(let message): return ["state": "failed", "error": message]
        }
    }

    private func send(status: String, json: [String: Any]?, origin: String?, on connection: NWConnection) {
        let body = json.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        var head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if let origin {
            head += "Access-Control-Allow-Origin: \(origin)\r\n"
            head += "Access-Control-Allow-Methods: GET, OPTIONS\r\n"
            head += "Access-Control-Allow-Headers: X-TubeVault\r\n"
            head += "Access-Control-Allow-Private-Network: true\r\n"
            head += "Access-Control-Max-Age: 600\r\n"
        }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
