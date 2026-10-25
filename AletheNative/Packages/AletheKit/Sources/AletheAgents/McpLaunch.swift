import Foundation

public struct McpLaunchServer: Equatable, Sendable {
    public var name: String
    public var command: String
    public var arguments: [String]
    public var environment: [String: String]
    public var url: String?
    public var headers: [String: String]

    public init(name: String, command: String, arguments: [String] = [], environment: [String: String] = [:]) {
        self.name = name
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.url = nil
        self.headers = [:]
    }

    public static func http(name: String, url: String, headers: [String: String] = [:]) -> McpLaunchServer {
        var server = McpLaunchServer(name: name, command: "")
        server.url = url
        server.headers = headers
        return server
    }

    public var isHTTP: Bool { url != nil }

    public static func deduplicated(_ servers: [McpLaunchServer]) -> [McpLaunchServer] {
        var seen: Set<String> = []
        return servers.filter { seen.insert($0.name).inserted }
    }
}

public enum McpLaunchConfig {
    public static func supports(_ kind: AgentKind) -> Bool {
        kind == .claude || kind == .codex || kind == .opencode
    }

    public static func needsFile(_ kind: AgentKind) -> Bool {
        kind == .claude || kind == .opencode
    }

    public static func file(for kind: AgentKind, servers: [McpLaunchServer]) -> Data? {
        switch kind {
        case .claude: claudeConfig(servers)
        case .opencode: opencodeConfig(servers)
        default: nil
        }
    }

    public static func claudeConfig(_ servers: [McpLaunchServer]) -> Data {
        var entries: [String: Any] = [:]
        for server in McpLaunchServer.deduplicated(servers) {
            if let url = server.url {
                var entry: [String: Any] = ["type": "http", "url": url]
                if !server.headers.isEmpty { entry["headers"] = server.headers }
                entries[server.name] = entry
                continue
            }
            var entry: [String: Any] = ["command": server.command, "args": server.arguments]
            if !server.environment.isEmpty { entry["env"] = server.environment }
            entries[server.name] = entry
        }
        return json(["mcpServers": entries])
    }

    public static func opencodeConfig(_ servers: [McpLaunchServer]) -> Data {
        var entries: [String: Any] = [:]
        for server in McpLaunchServer.deduplicated(servers) {
            if let url = server.url {
                var entry: [String: Any] = ["type": "remote", "url": url, "enabled": true]
                if !server.headers.isEmpty { entry["headers"] = server.headers }
                entries[server.name] = entry
                continue
            }
            var entry: [String: Any] = ["type": "local", "command": [server.command] + server.arguments, "enabled": true]
            if !server.environment.isEmpty { entry["environment"] = server.environment }
            entries[server.name] = entry
        }
        return json(["$schema": "https://opencode.ai/config.json", "mcp": entries])
    }

    public static func codexArguments(_ servers: [McpLaunchServer]) -> [String] {
        var arguments: [String] = []
        var seen: Set<String> = []
        for server in servers where !server.isHTTP {
            let key = codexKey(server.name)
            guard seen.insert(key).inserted else { continue }
            let prefix = "mcp_servers.\(key)"
            arguments += ["-c", "\(prefix).command=\(tomlString(server.command))"]
            arguments += ["-c", "\(prefix).args=[\(server.arguments.map(tomlString).joined(separator: ","))]"]
            if !server.environment.isEmpty {
                let pairs = server.environment.sorted { $0.key < $1.key }
                    .map { "\(tomlString($0.key))=\(tomlString($0.value))" }
                arguments += ["-c", "\(prefix).env={\(pairs.joined(separator: ","))}"]
            }
        }
        return arguments
    }

    static func codexKey(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let key = String(name.map { allowed.contains($0) ? $0 : "_" })
        return key.isEmpty ? "_" : key
    }

    static func tomlString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }
}
