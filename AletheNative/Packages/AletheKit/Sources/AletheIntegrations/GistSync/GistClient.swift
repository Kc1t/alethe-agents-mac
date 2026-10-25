import Foundation

public enum GistSyncError: Error, Equatable, Sendable {
    case emptyToken
    case invalidToken
    case notConnected
    case nothingToSync
    case noRemote
    case remoteMissingWorkspace
    case malformedGist
    case invalidRemoteFile(String)
    case newerFormat
    case http(Int)
    case transport(Int)
}

struct GistClient: Sendable {
    static let userAgent = "Alethe"
    static let apiVersion = "2022-11-28"

    let session: URLSession
    let apiBase: URL
    let token: String

    struct RemoteFile: Sendable {
        var content: String?
        var truncated: Bool
        var rawURL: URL?
    }

    func request(_ url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw GistSyncError.transport(error.code.rawValue)
        }
    }

    private func endpoint(_ path: String) -> URL { apiBase.appending(path: path) }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GistSyncError.malformedGist
        }
        return object
    }

    private static func check(_ status: Int) throws {
        if status == 401 { throw GistSyncError.invalidToken }
        guard (200..<300).contains(status) else { throw GistSyncError.http(status) }
    }

    func login() async throws -> String? {
        let (data, status) = try await send(request(endpoint("user")))
        try Self.check(status)
        return try Self.object(data)["login"] as? String
    }

    static func payload(files: [String: String], description: String) throws -> Data {
        let body: [String: Any] = [
            "description": description,
            "public": false,
            "files": files.mapValues { ["content": $0] },
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    func create(_ payload: Data) async throws -> String {
        let (data, status) = try await send(request(endpoint("gists"), method: "POST", body: payload))
        try Self.check(status)
        guard let id = try Self.object(data)["id"] as? String, !id.isEmpty else { throw GistSyncError.malformedGist }
        return id
    }

    func update(_ id: String, with payload: Data) async throws -> String {
        let (_, status) = try await send(request(endpoint("gists/\(id)"), method: "PATCH", body: payload))
        if status == 404 || status == 422 { return try await create(payload) }
        try Self.check(status)
        return id
    }

    func files(of id: String) async throws -> [String: RemoteFile] {
        let (data, status) = try await send(request(endpoint("gists/\(id)")))
        if status == 404 { throw GistSyncError.noRemote }
        try Self.check(status)
        guard let files = try Self.object(data)["files"] as? [String: Any] else { throw GistSyncError.malformedGist }
        var result: [String: RemoteFile] = [:]
        for (name, value) in files {
            guard let file = value as? [String: Any] else { continue }
            result[name] = RemoteFile(content: file["content"] as? String, truncated: file["truncated"] as? Bool ?? false,
                                      rawURL: (file["raw_url"] as? String).flatMap(URL.init(string:)))
        }
        return result
    }

    func content(of file: RemoteFile) async throws -> String? {
        guard file.truncated else { return file.content }
        guard let raw = file.rawURL else { return nil }
        guard isTrusted(raw) else { throw GistSyncError.malformedGist }
        let (data, status) = try await send(request(raw))
        try Self.check(status)
        return String(decoding: data, as: UTF8.self)
    }

    func isTrusted(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        if host == apiBase.host()?.lowercased(), url.scheme == apiBase.scheme { return true }
        guard url.scheme == "https" else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host == "githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
    }
}
