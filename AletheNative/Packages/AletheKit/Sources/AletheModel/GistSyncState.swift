import Foundation

public struct GistSyncState: Codable, Hashable, Sendable {
    public static let fileName = "github_sync.json"

    public var login: String?
    public var gistID: String?
    public var lastPushAt: Date?
    public var lastPullAt: Date?
    public var tauriGistID: String?

    public init(login: String? = nil, gistID: String? = nil, lastPushAt: Date? = nil, lastPullAt: Date? = nil,
                tauriGistID: String? = nil) {
        self.login = login
        self.gistID = gistID
        self.lastPushAt = lastPushAt
        self.lastPullAt = lastPullAt
        self.tauriGistID = tauriGistID
    }

    public var gistURL: URL? { gistID.flatMap { URL(string: "https://gist.github.com/\($0)") } }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func load(from url: URL) -> GistSyncState {
        guard let data = try? Data(contentsOf: url) else { return GistSyncState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(GistSyncState.self, from: data)) ?? GistSyncState()
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder().encode(self).write(to: url, options: .atomic)
    }
}

extension DataLocations {
    public func gistSync(_ id: ProfileID) -> URL { profileDirectory(id).appending(path: GistSyncState.fileName) }
}
