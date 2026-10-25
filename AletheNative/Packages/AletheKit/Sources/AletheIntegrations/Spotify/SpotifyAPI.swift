import Foundation

public enum SpotifyError: Error, Equatable, Sendable {
    case missingCredentials
    case loginInProgress
    case portBusy
    case listenerFailed(String)
    case browserUnavailable
    case timedOut
    case cancelled
    case stateMismatch
    case authorizationDenied(String)
    case missingCode
    case missingRefreshToken
    case tokenRequestFailed(status: Int, reason: String?)
    case refreshRejected
    case requestFailed(status: Int)
    case network(URLError.Code)
    case invalidResponse
    case secretStore(SecretStoreFailure)

    public enum SecretStoreFailure: Equatable, Sendable {
        case keychain(Int32)
        case undecodable
    }
}

public enum Spotify {
    public static let redirectURI = "http://127.0.0.1:8888/callback"
    public static let callbackPort: UInt16 = 8888
    public static let callbackPath = "/callback"
    public static let scopes = "user-read-currently-playing user-read-playback-state user-read-recently-played"
    public static let authorizeURL = "https://accounts.spotify.com/authorize"
    public static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    public static let nowPlayingURL = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!
    public static let recentlyPlayedURL = URL(string: "https://api.spotify.com/v1/me/player/recently-played?limit=1")!
    public static let loginTimeout: TimeInterval = 5 * 60
    public static let refreshMargin: TimeInterval = 30
    public static let stateLength = 24

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")

    public static func authorizeURL(clientID: String, state: String) -> URL {
        URL(string: "\(authorizeURL)?response_type=code&client_id=\(encode(clientID))&scope=\(encode(scopes))"
            + "&redirect_uri=\(encode(redirectURI))&state=\(encode(state))")!
    }

    public static func randomState(length: Int = stateLength) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(UInt8.random(in: 0...255, using: &generator) & 63)] })
    }

    static func formBody(_ fields: [(String, String)]) -> Data {
        Data(fields.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&").utf8)
    }
}

public struct SpotifyCredentials: Hashable, Sendable, CustomStringConvertible {
    public var clientID: String
    public var clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    public static func resolve(clientID: String?, clientSecret: String?,
                               environment: [String: String]) throws(SpotifyError) -> SpotifyCredentials {
        func pick(_ value: String?, _ variable: String) -> String {
            let chosen = value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ?? environment[variable] ?? ""
            return chosen.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let id = pick(clientID, "SPOTIFY_CLIENT_ID")
        let secret = pick(clientSecret, "SPOTIFY_CLIENT_SECRET")
        guard !id.isEmpty, !secret.isEmpty else { throw .missingCredentials }
        return SpotifyCredentials(clientID: id, clientSecret: secret)
    }

    var basicAuthorization: String {
        "Basic " + Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
    }

    public var description: String { "SpotifyCredentials(clientID: \(clientID.isEmpty ? "none" : "set"))" }
}

public struct SpotifyNowPlaying: Codable, Hashable, Sendable {
    public var playing: Bool
    public var track: String
    public var artist: String
    public var album: String
    public var coverURL: URL?
    public var durationMs: Int
    public var progressMs: Int
    public var trackURL: URL?

    public init(playing: Bool, track: String, artist: String, album: String, coverURL: URL?,
                durationMs: Int, progressMs: Int, trackURL: URL?) {
        self.playing = playing
        self.track = track
        self.artist = artist
        self.album = album
        self.coverURL = coverURL
        self.durationMs = durationMs
        self.progressMs = progressMs
        self.trackURL = trackURL
    }

    static func parse(item: Any?, playing: Bool, progressMs: Int) -> SpotifyNowPlaying? {
        guard let item = item as? [String: Any], let name = item["name"] as? String else { return nil }
        let artists = (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let album = item["album"] as? [String: Any]
        let cover = ((album?["images"] as? [[String: Any]])?.last?["url"] as? String).flatMap(URL.init(string:))
        let link = ((item["external_urls"] as? [String: Any])?["spotify"] as? String).flatMap(URL.init(string:))
        return SpotifyNowPlaying(
            playing: playing, track: name, artist: artists.joined(separator: ", "),
            album: album?["name"] as? String ?? "", coverURL: cover,
            durationMs: (item["duration_ms"] as? NSNumber)?.intValue ?? 0, progressMs: progressMs, trackURL: link)
    }

    static func parseCurrentlyPlaying(_ data: Data) -> SpotifyNowPlaying? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return parse(item: object["item"], playing: object["is_playing"] as? Bool ?? false,
                     progressMs: (object["progress_ms"] as? NSNumber)?.intValue ?? 0)
    }

    static func parseRecentlyPlayed(_ data: Data) -> SpotifyNowPlaying? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let first = (object["items"] as? [[String: Any]])?.first else { return nil }
        return parse(item: first["track"], playing: false, progressMs: 0)
    }
}

struct SpotifyTokenResponse: Decodable, Sendable {
    var accessToken: String
    var expiresIn: Double
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token"
    }

    static func errorCode(_ data: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
    }
}
