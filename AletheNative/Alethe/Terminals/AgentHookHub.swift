import AletheAgents
import AletheModel
import Foundation

@MainActor
final class AgentHookHub {
    let subagents = SubagentTracker()
    private var server: AgentHookServer?
    private var endpoint: String?
    static let folder = FileManager.default.temporaryDirectory.appending(path: "alethe-hooks-\(getpid())", directoryHint: .isDirectory)
    private var folder: URL { Self.folder }
    private var codexScript: URL?
    private var codexHookScript: URL?
    private var mcpHandler: AgentHookServer.McpHandler?

    var connection: (endpoint: String, token: String)? {
        guard let endpoint, let server else { return nil }
        return (endpoint, server.token)
    }

    func serveMcp(_ handler: AgentHookServer.McpHandler?) {
        mcpHandler = handler
        server?.setMcpHandler(handler)
    }

    func start(terminals: TerminalRegistry) async {
        guard server == nil else { return }
        let subagents = subagents
        let server = AgentHookServer { agent, tab, body in
            let codexSubagents = agent == AgentHookWiring.codexSubagentRoute
            if agent == "claude" || codexSubagents, let hook = SubagentHook.parse(body) {
                let source = codexSubagents ? "codex" : "claude"
                Task { @MainActor in subagents.ingest(hook, planner: tab, sourceAgent: source) }
            }
            if codexSubagents { return }
            let event = agent == "codex" ? AgentHookEvent.codex(body) : AgentHookEvent.claude(body)
            guard let event else { return }
            Task { @MainActor in terminals.apply(event, to: TabID(rawValue: tab)) }
        }
        self.server = server
        server.setMcpHandler(mcpHandler)
        endpoint = await server.start()
        guard let endpoint else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let script = folder.appending(path: "codex-notify.sh")
        if (try? Data(AgentHookWiring.codexForwarder(endpoint: endpoint, token: server.token).utf8).write(to: script)) != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            codexScript = script
        }
        let hookScript = folder.appending(path: "codex-hook.sh")
        if (try? Data(AgentHookWiring.codexHookForwarder(endpoint: endpoint, token: server.token).utf8).write(to: hookScript)) != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hookScript.path)
            codexHookScript = hookScript
        }
    }

    func launch(for tab: TabID, kind: AgentKind, orchestrator: Bool = false) -> AgentLaunchRequest.HookLaunch? {
        guard let endpoint, let server else { return nil }
        switch kind {
        case .claude:
            let file = folder.appending(path: "claude-\(tab.rawValue).json")
            guard (try? AgentHookWiring.claudeSettings(endpoint: endpoint, token: server.token, tab: tab.rawValue,
                                                       orchestrator: orchestrator)
                .write(to: file)) != nil else { return nil }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return AgentLaunchRequest.HookLaunch(claudeSettingsPath: file.path)
        case .codex:
            guard let codexScript else { return nil }
            var arguments = AgentHookWiring.codexArguments(script: codexScript.path, tab: tab.rawValue)
            if orchestrator, let codexHookScript {
                arguments += AgentHookWiring.codexSubagentArguments(script: codexHookScript.path, tab: tab.rawValue)
            }
            return AgentLaunchRequest.HookLaunch(codexArguments: arguments)
        default:
            return nil
        }
    }

    func reportsTurns(_ kind: AgentKind) -> Bool { endpoint != nil && kind == .claude }

    func stop() {
        server?.stop()
        try? FileManager.default.removeItem(at: folder)
    }
}
