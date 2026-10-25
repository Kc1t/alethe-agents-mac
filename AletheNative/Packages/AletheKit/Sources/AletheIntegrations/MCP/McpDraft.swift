import Foundation

public enum McpTransportKind: String, Hashable, Sendable, CaseIterable {
    case stdio
    case http
    case sse
}

public struct McpEnvDraft: Hashable, Sendable, Identifiable {
    public let id: UUID
    public var key: String
    public var value: String
    public var passthrough: Bool
    public var secret: Bool
    public var required: Bool
    public var hint: String?
    public var stored: McpEnvEntry?

    public init(key: String = "", value: String = "", passthrough: Bool = false, secret: Bool = false,
                required: Bool = false, hint: String? = nil, stored: McpEnvEntry? = nil) {
        id = UUID()
        self.key = key
        self.value = value
        self.passthrough = passthrough
        self.secret = secret
        self.required = required
        self.hint = hint
        self.stored = stored
    }

    public var storedPreview: String? {
        stored?.literal.flatMap { $0.isEmpty ? nil : Secret.mask($0) }
    }

    public var keepsStoredLiteral: Bool {
        !passthrough && value.isEmpty && stored?.literal != nil
    }

    public var entry: McpEnvEntry? {
        let name = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let typed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored {
            if passthrough, let from = stored.passthroughFrom, typed.isEmpty || typed == from { return stored }
            if !passthrough, value.isEmpty, let literal = stored.literal {
                return stored.passthroughFrom == nil ? stored : .literal(literal)
            }
        }
        if passthrough { return .passthrough(typed.isEmpty ? name : typed) }
        return .literal(value)
    }

    fileprivate static func rows(_ map: McpEnvMap) -> [McpEnvDraft] {
        map.sorted { $0.key < $1.key }.map { key, entry in
            McpEnvDraft(key: key, value: entry.passthroughFrom ?? "", passthrough: entry.passthroughFrom != nil,
                        secret: entry.literal != nil, stored: entry)
        }
    }

    fileprivate static func rows(_ hints: [McpEnvHint]) -> [McpEnvDraft] {
        hints.map { hint in
            McpEnvDraft(key: hint.name, value: hint.secret ? "" : hint.default ?? "", secret: hint.secret,
                        required: hint.required, hint: hint.description)
        }
    }
}

public struct McpServerDraft: Hashable, Sendable {
    public var name: String
    public var kind: McpTransportKind
    public var command: String
    public var arguments: String
    public var cwd: String
    public var url: String
    public var env: [McpEnvDraft]
    public var headers: [McpEnvDraft]
    public private(set) var original: McpServer?

    public init() {
        name = ""
        kind = .stdio
        command = ""
        arguments = ""
        cwd = ""
        url = ""
        env = []
        headers = []
    }

    public init(editing server: McpServer) {
        self.init()
        original = server
        name = server.name
        env = McpEnvDraft.rows(server.env)
        switch server.transport {
        case .stdio(let command, let arguments, let cwd):
            self.command = command
            self.arguments = arguments.joined(separator: "\n")
            self.cwd = cwd ?? ""
        case .http(let url, let headers):
            kind = .http
            self.url = url
            self.headers = McpEnvDraft.rows(headers)
        case .sse(let url, let headers):
            kind = .sse
            self.url = url
            self.headers = McpEnvDraft.rows(headers)
        }
    }

    public init(option: McpInstallOption, name: String) {
        self.init()
        self.name = name
        switch option.kind {
        case .stdio:
            command = option.command ?? ""
            arguments = option.args.joined(separator: "\n")
        case .http:
            kind = .http
            url = option.url ?? ""
        case .sse:
            kind = .sse
            url = option.url ?? ""
        }
        env = McpEnvDraft.rows(option.env)
        headers = McpEnvDraft.rows(option.headers)
    }

    public var isEditing: Bool { original != nil }

    public var missingRequired: [String] {
        (env + headers).filter { $0.required && $0.value.isEmpty && $0.stored == nil }.map(\.key)
    }

    public func server() throws(McpStoreError) -> McpServer {
        func map(_ rows: [McpEnvDraft]) -> McpEnvMap {
            var out: McpEnvMap = [:]
            for row in rows {
                if let entry = row.entry { out[row.key.trimmingCharacters(in: .whitespacesAndNewlines)] = entry }
            }
            return out
        }
        let transport: McpTransport
        switch kind {
        case .stdio:
            let arguments = arguments.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let cwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
            transport = .stdio(command: command, arguments: arguments, cwd: cwd.isEmpty ? nil : cwd)
        case .http:
            transport = .http(url: url, headers: map(headers))
        case .sse:
            transport = .sse(url: url, headers: map(headers))
        }
        var server = original ?? McpServer(name: name, transport: transport)
        server.name = name
        server.transport = transport
        server.env = map(env)
        return try McpStore.validated(server)
    }
}

extension McpTransport {
    public var summary: String { view.summary }
}

extension McpTransportView {
    public var summary: String {
        switch self {
        case .stdio(let command, let arguments, _): ([command] + arguments).filter { !$0.isEmpty }.joined(separator: " ")
        case .http(let url, _), .sse(let url, _): url
        }
    }
}

extension McpServerGroup {
    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return name.lowercased().contains(needle)
            || agents.contains { $0.rawValue.contains(needle) }
            || records.contains { $0.server.transport.summary.lowercased().contains(needle) }
    }

    public func isOn(anyOf picked: Set<McpAgent>) -> Bool {
        picked.isEmpty || agents.contains(where: picked.contains)
    }
}

public enum McpSnapshotIssue: String, Hashable, Sendable {
    case unsupported
    case unreadable
    case missing
    case readOnly
}

extension McpAgentSnapshot {
    public var issue: McpSnapshotIssue? {
        if sources.isEmpty { return .unsupported }
        if sources.contains(where: { $0.parseError != nil }) { return .unreadable }
        if sources.allSatisfy({ !$0.exists }) { return .missing }
        if sources.contains(where: { $0.exists && !$0.writable }) { return .readOnly }
        return nil
    }

    public var isWritable: Bool {
        sources.contains { $0.parseError == nil && $0.writable }
    }
}

extension McpStore {
    public func sources(for agent: McpAgent, scope: McpScope, repository: URL?) -> [McpSource] {
        sources(agent, scope, repository)
    }

    public func source(of record: McpServerRecord, repository: URL?) -> McpSource? {
        let path = record.sourceURL.standardizedFileURL.path(percentEncoded: false)
        return sources(record.agent, record.scope, repository).first {
            $0.kind == record.sourceKind && $0.url.standardizedFileURL.path(percentEncoded: false) == path
        }
    }
}
