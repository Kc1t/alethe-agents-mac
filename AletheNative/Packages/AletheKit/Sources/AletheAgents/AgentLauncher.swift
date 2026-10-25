import Foundation

public struct AgentLaunchRequest: Sendable {
    public var kind: AgentKind
    public var workingDirectory: String?
    public var extraArguments: [String]
    public var sessionID: String?
    public var unrestricted: Bool
    public var hooks: HookLaunch?
    public var mcpServers: [McpLaunchServer]
    public var mcpConfigPath: String?
    public var environment: [String: String]

    public struct HookLaunch: Sendable {
        public var claudeSettingsPath: String?
        public var codexArguments: [String]

        public init(claudeSettingsPath: String? = nil, codexArguments: [String] = []) {
            self.claudeSettingsPath = claudeSettingsPath
            self.codexArguments = codexArguments
        }
    }

    public init(kind: AgentKind, workingDirectory: String? = nil, extraArguments: [String] = [],
                sessionID: String? = nil, unrestricted: Bool = false, hooks: HookLaunch? = nil,
                mcpServers: [McpLaunchServer] = [], mcpConfigPath: String? = nil, environment: [String: String] = [:]) {
        self.kind = kind
        self.workingDirectory = workingDirectory
        self.extraArguments = extraArguments
        self.sessionID = sessionID
        self.unrestricted = unrestricted
        self.hooks = hooks
        self.mcpServers = mcpServers
        self.mcpConfigPath = mcpConfigPath
        self.environment = environment
    }
}

public struct AgentCommand: Equatable, Sendable {
    public var shellCommand: String?
    public var workingDirectory: String?
    public var environment: [String: String?]
    public var sessionID: String?
    public var createdSession: Bool
    public var executable: String?
}

public enum AgentLaunchError: Error, Equatable, Sendable {
    case unknownAgent(String)
    case launcherNotFound(command: String)
}

public struct AgentLauncher: Sendable {
    public let registry: AgentRegistry
    public let launchers: LauncherCache
    public var overrides: [String: String]

    public init(registry: AgentRegistry = .builtin, launchers: LauncherCache = LauncherCache(),
                overrides: [String: String] = [:]) {
        self.registry = registry
        self.launchers = launchers
        self.overrides = overrides
    }

    public static let scrubbedVariables = [
        "EDITOR", "VISUAL", "TERM_PROGRAM_VERSION",
        "VSCODE_CWD", "VSCODE_IPC_HOOK", "VSCODE_IPC_HOOK_CLI", "VSCODE_GIT_ASKPASS_NODE",
        "VSCODE_GIT_ASKPASS_EXTRA_ARGS", "VSCODE_GIT_ASKPASS_MAIN", "VSCODE_GIT_IPC_HANDLE",
        "GIT_ASKPASS", "ELECTRON_RUN_AS_NODE",
        "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDECODE_PARENT_PID", "CLAUDE_PID",
        "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_BRIDGE_SESSION_ID",
        "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN",
        "CLAUDE_CODE_EXECPATH",
    ]

    public func command(for request: AgentLaunchRequest,
                        makeSessionID: () -> String = { UUID().uuidString.lowercased() }) throws(AgentLaunchError) -> AgentCommand {
        guard let descriptor = registry.descriptor(for: request.kind) else {
            throw .unknownAgent(request.kind.rawValue)
        }
        var environment: [String: String?] = [:]
        for key in Self.scrubbedVariables { environment[key] = .some(nil) }
        for (key, value) in request.environment { environment[key] = .some(value) }

        guard let cli = descriptor.cliCommand else {
            return AgentCommand(shellCommand: nil, workingDirectory: request.workingDirectory, environment: environment,
                                sessionID: nil, createdSession: false, executable: nil)
        }
        guard let executable = launchers.resolve(cli, override: overrides[request.kind.rawValue]) else {
            throw .launcherNotFound(command: cli)
        }

        var base = descriptor.defaultArguments + request.extraArguments
        if request.unrestricted, let flag = descriptor.unrestrictedFlag, !base.contains(flag) {
            base.append(flag)
        }
        var session = AgentArguments.build(for: request.kind, base: base, sessionID: request.sessionID,
                                           makeSessionID: makeSessionID)
        let mcpFile = request.mcpServers.isEmpty ? nil : request.mcpConfigPath
        if case .claude = request.kind {
            var flags = mcpFile.map { ["--mcp-config=\($0)"] } ?? []
            if let path = request.hooks?.claudeSettingsPath { flags += ["--settings", path] }
            session.arguments.insert(contentsOf: flags, at: min(2, session.arguments.count))
        } else if case .codex = request.kind {
            let mcp = McpLaunchConfig.codexArguments(request.mcpServers)
            session.arguments = (request.hooks?.codexArguments ?? []) + mcp + session.arguments
        } else if case .opencode = request.kind {
            if let mcpFile { environment["OPENCODE_CONFIG"] = mcpFile }
        }
        if request.kind == .opencode {
            environment["OPENTUI_FORCE_EXPLICIT_WIDTH"] = "false"
        }

        let directory = (executable as NSString).deletingLastPathComponent
        let line = "export PATH=\(Self.quoted(directory)):\"$PATH\"; exec "
            + ([executable] + session.arguments).map(Self.quoted).joined(separator: " ")
        return AgentCommand(shellCommand: line, workingDirectory: request.workingDirectory, environment: environment,
                            sessionID: session.sessionID, createdSession: session.createdSession, executable: executable)
    }

    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
