import Foundation

public struct RemoteRequest: Sendable, Equatable {
    public var method: String
    public var target: String
    public var headers: [String: String]
    public var body: Data
    public var peerAddress: String

    public init(method: String, target: String, headers: [String: String] = [:], body: Data = Data(), peerAddress: String) {
        self.method = method
        self.target = target
        var lowered: [String: String] = [:]
        for (name, value) in headers where lowered[name.lowercased()] == nil {
            lowered[name.lowercased()] = value
        }
        self.headers = lowered
        self.body = body
        self.peerAddress = peerAddress
    }

    public var path: String {
        target.firstIndex(of: "?").map { String(target[..<$0]) } ?? target
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    public func queryValue(_ key: String) -> String? {
        RemoteText.queryValue(target, key)
    }

    public var bearerToken: String {
        guard let value = header("authorization") else { return "" }
        for prefix in ["Bearer ", "bearer "] where value.hasPrefix(prefix) {
            return String(value.dropFirst(prefix.count))
        }
        return ""
    }
}

public struct RemoteResponse: Sendable, Equatable {
    public enum Caching: Sendable, Equatable {
        case noStore, immutable

        public var headerValue: String {
            switch self {
            case .noStore: "no-store"
            case .immutable: "public, max-age=31536000, immutable"
            }
        }
    }

    public enum SizeLimit: Sendable, Equatable {
        case standard
        case large

        public var bytes: Int {
            switch self {
            case .standard: RemoteLimits.maxBody
            case .large: RemoteLimits.maxStaticAsset
            }
        }
    }

    public var status: Int
    public var contentType: String
    public var body: Data
    public var caching: Caching
    public var sizeLimit: SizeLimit

    public init(status: Int, contentType: String, body: Data, caching: Caching = .noStore, sizeLimit: SizeLimit = .standard) {
        self.status = status
        self.contentType = contentType
        self.body = body
        self.caching = caching
        self.sizeLimit = sizeLimit
    }

    public static func json(_ status: Int, _ body: Data, sizeLimit: SizeLimit = .standard) -> RemoteResponse {
        RemoteResponse(status: status, contentType: "application/json", body: body, sizeLimit: sizeLimit)
    }

    public static func json<Value: Encodable>(_ status: Int, encoding value: Value, sizeLimit: SizeLimit = .standard) -> RemoteResponse {
        guard let data = try? RemoteFrame.encoder.encode(value) else {
            return error(500, "Internal error")
        }
        return json(status, data, sizeLimit: sizeLimit)
    }

    public static func error(_ status: Int, _ message: String) -> RemoteResponse {
        json(status, encoding: ["error": message])
    }

    public static let noContent = RemoteResponse(status: 204, contentType: "text/plain", body: Data())
    public static let notFound = RemoteResponse(status: 404, contentType: "text/plain", body: Data("Not found".utf8))

    public var exceedsLimit: Bool { body.count > sizeLimit.bytes }

    public var reasonPhrase: String {
        switch status {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 409: "Conflict"
        case 429: "Too Many Requests"
        default: "Error"
        }
    }

    public func head() -> String {
        "HTTP/1.1 \(status) \(reasonPhrase)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n"
            + "Cache-Control: \(caching.headerValue)\r\n"
            + "Referrer-Policy: no-referrer\r\n"
            + "X-Content-Type-Options: nosniff\r\n"
            + "Content-Security-Policy: \(Self.contentSecurityPolicy)\r\n\r\n"
    }

    public static let contentSecurityPolicy = "default-src 'self'; connect-src 'self' ws:; img-src 'self' data:; "
        + "style-src 'self' 'unsafe-inline'; script-src 'self'; base-uri 'none'; frame-ancestors 'none'"
}

public protocol RemoteRouter: Sendable {
    func route(_ request: RemoteRequest) async -> RemoteResponse
}

public struct RemoteTerminalSize: Codable, Equatable, Sendable {
    public var cols: Int
    public var rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }

    public static let fallback = RemoteTerminalSize(cols: 80, rows: 24)
}

public enum RemoteInputError: Error, Equatable, Sendable {
    case notFound
    case notRunning
    case failed(String)
}

public enum RemoteTerminalOutput: Equatable, Sendable {
    case data(terminalID: String, text: String)
    case exit(terminalID: String, reason: String)

    public var terminalID: String {
        switch self {
        case .data(let id, _), .exit(let id, _): id
        }
    }

    public var frame: String {
        switch self {
        case .data(let id, let text): RemoteFrame.encode(["type": "pty_output", "ptyId": id, "text": text])
        case .exit(let id, let reason): RemoteFrame.encode(["type": "pty_exit", "ptyId": id, "reason": reason])
        }
    }
}

public protocol RemoteTerminalSource: Sendable {
    func scrollbackTail(terminalID: String, maxBytes: Int) async -> String
    func size(terminalID: String) async -> RemoteTerminalSize?
    func write(terminalID: String, text: String) async throws(RemoteInputError)
    func output() -> AsyncStream<RemoteTerminalOutput>
}

public struct RemoteSharedTab: Codable, Equatable, Sendable {
    public var terminalID: String
    public var agent: String
    public var cwd: String
    public var sessionID: String?

    public init(terminalID: String, agent: String, cwd: String, sessionID: String?) {
        self.terminalID = terminalID
        self.agent = agent
        self.cwd = cwd
        self.sessionID = sessionID
    }

    public var isControllableAgent: Bool { agent == "claude" || agent == "codex" }
    public var isShell: Bool { agent == "shell" }
}

public struct RemoteWorkspaceSnapshot: Codable, Equatable, Sendable {
    public struct Group: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var color: String?

        public init(id: String, name: String, color: String?) {
            self.id = id
            self.name = name
            self.color = color
        }
    }

    public struct Chat: Codable, Equatable, Sendable {
        public var id: String
        public var ptyId: String
        public var name: String
        public var agent: String
        public var terminalId: String

        public init(id: String, ptyId: String, name: String, agent: String, terminalId: String) {
            self.id = id
            self.ptyId = ptyId
            self.name = name
            self.agent = agent
            self.terminalId = terminalId
        }
    }

    public struct Project: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var groupId: String?
        public var color: String?
        public var chats: [Chat]

        public init(id: String, name: String, groupId: String?, color: String?, chats: [Chat]) {
            self.id = id
            self.name = name
            self.groupId = groupId
            self.color = color
            self.chats = chats
        }
    }

    public var groups: [Group]
    public var projects: [Project]

    public init(groups: [Group], projects: [Project]) {
        self.groups = groups
        self.projects = projects
    }
}

public struct RemoteAppearance: Codable, Equatable, Sendable {
    public var uiTheme: String
    public var appIconTheme: String
    public var language: String
    public var motionPreference: String
    public var colorScheme: String

    public init(uiTheme: String, appIconTheme: String, language: String, motionPreference: String, colorScheme: String) {
        self.uiTheme = uiTheme
        self.appIconTheme = appIconTheme
        self.language = language
        self.motionPreference = motionPreference
        self.colorScheme = colorScheme
    }
}

public struct RemoteQuestionOption: Codable, Equatable, Sendable {
    public var label: String
    public var description: String

    public init(label: String, description: String) {
        self.label = label
        self.description = description
    }
}

public struct RemoteQuestion: Codable, Equatable, Sendable {
    public var id: String
    public var header: String
    public var question: String
    public var multiSelect: Bool
    public var options: [RemoteQuestionOption]

    public init(id: String, header: String, question: String, multiSelect: Bool, options: [RemoteQuestionOption]) {
        self.id = id
        self.header = header
        self.question = question
        self.multiSelect = multiSelect
        self.options = options
    }
}

public struct RemoteQuestionSet: Codable, Equatable, Sendable {
    public var id: String
    public var questions: [RemoteQuestion]

    public init(id: String, questions: [RemoteQuestion]) {
        self.id = id
        self.questions = questions
    }
}

public struct RemoteTranscript: Codable, Equatable, Sendable {
    public struct Message: Codable, Equatable, Sendable {
        public var role: String
        public var text: String
        public var questionSetId: String?
        public var questions: [RemoteQuestion]?

        public init(role: String, text: String, questionSetId: String? = nil, questions: [RemoteQuestion]? = nil) {
            self.role = role
            self.text = text
            self.questionSetId = questionSetId
            self.questions = questions
        }
    }

    public var sessionId: String?
    public var revision: UInt64
    public var unchanged: Bool
    public var messages: [Message]

    public init(sessionId: String?, revision: UInt64, unchanged: Bool, messages: [Message]) {
        self.sessionId = sessionId
        self.revision = revision
        self.unchanged = unchanged
        self.messages = messages
    }
}

public protocol RemoteWorkspaceSource: Sendable {
    func sharedTabs() async -> [RemoteSharedTab]
    func snapshot() async -> RemoteWorkspaceSnapshot
    func appearance() async -> RemoteAppearance
    func transcript(for tab: RemoteSharedTab, since: UInt64?, limit: Int) async throws -> RemoteTranscript
    func activeQuestions(for tab: RemoteSharedTab) async -> RemoteQuestionSet?
}

public extension RemoteWorkspaceSource {
    func sharedTab(_ terminalID: String) async -> RemoteSharedTab? {
        await sharedTabs().first { $0.terminalID == terminalID }
    }
}

public struct RemoteAsset: Sendable, Equatable {
    public var data: Data
    public var contentType: String
    public var caching: RemoteResponse.Caching

    public init(data: Data, contentType: String, caching: RemoteResponse.Caching) {
        self.data = data
        self.contentType = contentType
        self.caching = caching
    }

    public var response: RemoteResponse {
        RemoteResponse(status: 200, contentType: contentType, body: data, caching: caching, sizeLimit: .large)
    }
}

public protocol RemoteAssetSource: Sendable {
    func asset(at path: String, appIconTheme: String) async -> RemoteAsset?
}

public struct RemoteMessageEvent: Codable, Equatable, Sendable {
    public var terminalID: String
    public var deviceID: Int
    public var deviceName: String
    public var preview: String

    public init(terminalID: String, deviceID: Int, deviceName: String, preview: String) {
        self.terminalID = terminalID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.preview = RemoteText.truncated(preview, to: RemoteLimits.maxPreview)
    }
}

public enum RemoteEvent: Equatable, Sendable {
    case message(RemoteMessageEvent)
    case startFailed
    case autoDisabled
}

public enum RemoteFrame {
    public static let authenticated = encode(["type": "authenticated"])
    public static let expired = encode(["type": "error", "reason": "expired", "message": "Remote session expired"])
    public static let unauthorized = encode(["type": "error", "reason": "unauthorized", "message": "Remote session is not valid"])

    public static func scrollback(terminalID: String, text: String, size: RemoteTerminalSize) -> String {
        struct Payload: Encodable {
            let type = "scrollback"
            let ptyId: String
            let text: String
            let cols: Int
            let rows: Int
        }
        return encode(Payload(ptyId: terminalID, text: text, cols: size.cols, rows: size.rows))
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    static func encode<Value: Encodable>(_ value: Value) -> String {
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
