import AletheAgents
import Foundation

public enum McpScope: String, Hashable, Sendable, Codable, CaseIterable {
    case global
    case project
}

public enum McpSourceKind: String, Hashable, Sendable, Codable, CaseIterable {
    case user
    case local
    case project

    public init?(parsing raw: String) {
        self.init(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

public enum McpAgent: String, Hashable, Sendable, Codable, CaseIterable, CustomStringConvertible {
    case claude
    case codex
    case cursor
    case opencode
    case antigravity

    public init?(parsing raw: String) {
        let normalized = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let aliases = ["cursor-agent": "cursor", "agy": "antigravity"]
        self.init(rawValue: aliases[normalized] ?? normalized)
    }

    public init?(kind: AgentKind) {
        self.init(rawValue: kind.rawValue)
    }

    public var agentKind: AgentKind { AgentKind(rawValue: rawValue) }

    public var description: String { rawValue }
}

public struct McpEnvEntry: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var literal: String?
    public var passthroughFrom: String?

    public init(literal: String? = nil, passthroughFrom: String? = nil) {
        self.literal = literal
        self.passthroughFrom = passthroughFrom
    }

    public static func literal(_ value: String) -> McpEnvEntry { McpEnvEntry(literal: value) }
    public static func passthrough(_ name: String) -> McpEnvEntry { McpEnvEntry(passthroughFrom: name) }

    public var view: McpEnvEntryView {
        McpEnvEntryView(
            literal: literal.map { McpLiteralView(preview: Secret.mask($0), isEmpty: $0.isEmpty) },
            passthroughFrom: passthroughFrom
        )
    }

    public var description: String {
        var parts: [String] = []
        if let literal { parts.append("literal: \(Secret.mask(literal))") }
        if let passthroughFrom { parts.append("passthrough: \(passthroughFrom)") }
        return "McpEnvEntry(\(parts.joined(separator: ", ")))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["literal": literal.map(Secret.mask) as Any, "passthroughFrom": passthroughFrom as Any])
    }
}

public typealias McpEnvMap = [String: McpEnvEntry]

public struct McpLiteralView: Hashable, Sendable {
    public let preview: String
    public let isEmpty: Bool
}

public struct McpEnvEntryView: Hashable, Sendable {
    public let literal: McpLiteralView?
    public let passthroughFrom: String?
}

public enum McpTransport: Hashable, Sendable {
    case stdio(command: String, arguments: [String], cwd: String?)
    case http(url: String, headers: McpEnvMap)
    case sse(url: String, headers: McpEnvMap)

    public var isRemote: Bool {
        if case .stdio = self { return false }
        return true
    }

    public var headers: McpEnvMap? {
        if case .http(_, let headers) = self { return headers }
        if case .sse(_, let headers) = self { return headers }
        return nil
    }

    public var view: McpTransportView {
        if case .stdio(let command, let arguments, let cwd) = self {
            return .stdio(command: command, arguments: arguments, cwd: cwd)
        }
        if case .http(let url, let headers) = self { return .http(url: url, headers: headers.mapValues(\.view)) }
        guard case .sse(let url, let headers) = self else { preconditionFailure("Unknown MCP transport") }
        return .sse(url: url, headers: headers.mapValues(\.view))
    }
}

public enum McpTransportView: Hashable, Sendable {
    case stdio(command: String, arguments: [String], cwd: String?)
    case http(url: String, headers: [String: McpEnvEntryView])
    case sse(url: String, headers: [String: McpEnvEntryView])
}

public struct McpTimeouts: Hashable, Sendable, Codable {
    public var startupSeconds: UInt32?
    public var toolSeconds: UInt32?

    public init(startupSeconds: UInt32? = nil, toolSeconds: UInt32? = nil) {
        self.startupSeconds = startupSeconds
        self.toolSeconds = toolSeconds
    }

    public var isEmpty: Bool { startupSeconds == nil && toolSeconds == nil }
}

public struct McpServer: Hashable, Sendable {
    public var name: String
    public var transport: McpTransport
    public var env: McpEnvMap
    public var enabled: Bool
    public var timeouts: McpTimeouts
    public var bearerTokenEnvVar: String?

    public init(
        name: String,
        transport: McpTransport,
        env: McpEnvMap = [:],
        enabled: Bool = true,
        timeouts: McpTimeouts = McpTimeouts(),
        bearerTokenEnvVar: String? = nil
    ) {
        self.name = name
        self.transport = transport
        self.env = env
        self.enabled = enabled
        self.timeouts = timeouts
        self.bearerTokenEnvVar = bearerTokenEnvVar
    }

    public var view: McpServerView {
        McpServerView(
            name: name,
            transport: transport.view,
            env: env.mapValues(\.view),
            enabled: enabled,
            timeouts: timeouts,
            bearerTokenEnvVar: bearerTokenEnvVar
        )
    }
}

public struct McpServerView: Hashable, Sendable {
    public let name: String
    public let transport: McpTransportView
    public let env: [String: McpEnvEntryView]
    public let enabled: Bool
    public let timeouts: McpTimeouts
    public let bearerTokenEnvVar: String?
}

public struct McpServerRecord: Hashable, Sendable {
    public var server: McpServer
    public var agent: McpAgent
    public var scope: McpScope
    public var sourceKind: McpSourceKind
    public var sourceURL: URL
    public var managedByImport: String?

    public init(server: McpServer, agent: McpAgent, scope: McpScope, sourceKind: McpSourceKind,
                sourceURL: URL, managedByImport: String? = nil) {
        self.server = server
        self.agent = agent
        self.scope = scope
        self.sourceKind = sourceKind
        self.sourceURL = sourceURL
        self.managedByImport = managedByImport
    }

    public var view: McpServerRecordView {
        McpServerRecordView(server: server.view, agent: agent, scope: scope, sourceKind: sourceKind,
                            sourceURL: sourceURL, managedByImport: managedByImport)
    }
}

public struct McpServerRecordView: Hashable, Sendable {
    public let server: McpServerView
    public let agent: McpAgent
    public let scope: McpScope
    public let sourceKind: McpSourceKind
    public let sourceURL: URL
    public let managedByImport: String?
}

public struct McpSourceState: Hashable, Sendable {
    public var kind: McpSourceKind
    public var url: URL
    public var exists: Bool
    public var writable: Bool
    public var parseError: McpConfigError?
    public var modificationDate: Date?

    public init(kind: McpSourceKind, url: URL, exists: Bool, writable: Bool,
                parseError: McpConfigError? = nil, modificationDate: Date? = nil) {
        self.kind = kind
        self.url = url
        self.exists = exists
        self.writable = writable
        self.parseError = parseError
        self.modificationDate = modificationDate
    }
}

public struct McpAgentSnapshot: Hashable, Sendable {
    public var agent: McpAgent
    public var scope: McpScope
    public var sources: [McpSourceState]
    public var servers: [McpServerRecord]

    public init(agent: McpAgent, scope: McpScope, sources: [McpSourceState] = [], servers: [McpServerRecord] = []) {
        self.agent = agent
        self.scope = scope
        self.sources = sources
        self.servers = servers
    }
}

public struct McpCapability: Hashable, Sendable {
    public let agent: McpAgent
    public let projectScope: Bool
    public let enabledFlag: Bool
    public let envPassthrough: Bool
    public let timeouts: Bool
    public let headers: Bool
    public let remote: Bool
}

extension McpAgent {
    public var capability: McpCapability {
        if self == .codex {
            return McpCapability(agent: self, projectScope: true, enabledFlag: true, envPassthrough: true,
                                 timeouts: true, headers: false, remote: true)
        }
        if self == .opencode {
            return McpCapability(agent: self, projectScope: true, enabledFlag: true, envPassthrough: true,
                                 timeouts: false, headers: true, remote: true)
        }
        return McpCapability(agent: self, projectScope: self != .antigravity, enabledFlag: false, envPassthrough: false,
                             timeouts: false, headers: true, remote: true)
    }
}

public struct McpUnsupportedField: Hashable, Sendable {
    public let agent: McpAgent
    public let field: String
    public let detail: String

    public init(agent: McpAgent, field: String, detail: String = "") {
        self.agent = agent
        self.field = field
        self.detail = detail
    }
}

extension McpServer {
    public func unsupportedFields(for agent: McpAgent) -> [McpUnsupportedField] {
        let caps = agent.capability
        var out: [McpUnsupportedField] = []
        if !caps.envPassthrough {
            let entries = env.sorted { $0.key < $1.key }.map { ("env.\($0.key)", $0.value) }
                + (transport.headers ?? [:]).sorted { $0.key < $1.key }.map { ("headers.\($0.key)", $0.value) }
            for (field, entry) in entries {
                if let from = entry.passthroughFrom {
                    out.append(McpUnsupportedField(agent: agent, field: field, detail: from))
                }
            }
        }
        if !caps.timeouts && !timeouts.isEmpty {
            out.append(McpUnsupportedField(agent: agent, field: "timeouts"))
        }
        if !caps.remote && transport.isRemote {
            out.append(McpUnsupportedField(agent: agent, field: "transport"))
        }
        if !caps.headers, let headers = transport.headers, !headers.isEmpty {
            out.append(McpUnsupportedField(agent: agent, field: "headers"))
        }
        if bearerTokenEnvVar != nil && agent != .codex {
            out.append(McpUnsupportedField(agent: agent, field: "bearerTokenEnvVar"))
        }
        return out
    }
}

extension McpServer {
    public init(launch: McpLaunchServer) {
        if let url = launch.url {
            self.init(name: launch.name, transport: .http(url: url, headers: launch.headers.mapValues(McpEnvEntry.literal)))
            return
        }
        self.init(
            name: launch.name,
            transport: .stdio(command: launch.command, arguments: launch.arguments, cwd: nil),
            env: launch.environment.mapValues(McpEnvEntry.literal)
        )
    }

    public var launchServer: McpLaunchServer? {
        guard case .stdio(let command, let arguments, nil) = transport else { return nil }
        var environment: [String: String] = [:]
        for (key, entry) in env {
            guard entry.passthroughFrom == nil, let literal = entry.literal else { return nil }
            environment[key] = literal
        }
        return McpLaunchServer(name: name, command: command, arguments: arguments, environment: environment)
    }
}
