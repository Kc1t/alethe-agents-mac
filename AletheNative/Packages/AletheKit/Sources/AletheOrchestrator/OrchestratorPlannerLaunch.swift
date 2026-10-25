import Foundation
import AletheAgents

public enum OrchestratorPlannerLaunch {
    public static let serverName = OrchestratorMCP.serverName
    public static let tokenHeader = "X-Alethe-Token"
    public static let plannerHeader = "X-Alethe-Planner"
    public static let helperName = "alethe-orchestrator-mcp"
    public static let bridgeFlag = "--bridge"

    public static func supports(_ kind: AgentKind) -> Bool { kind == .claude || kind == .codex }

    public static func usesBridge(_ kind: AgentKind) -> Bool { kind == .codex }

    public static func planner(tab: String, label: String, kind: AgentKind) -> Planner? {
        guard supports(kind) else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return Planner(id: tab, label: trimmed.isEmpty ? tab : trimmed, agent: kind.rawValue)
    }

    public static func server(endpoint: String, token: String, planner: String) -> McpLaunchServer {
        let base = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        return .http(name: serverName, url: "\(base)/mcp", headers: [tokenHeader: token, plannerHeader: planner])
    }

    public static func bridgeServer(helper: String, bridgeFile: String) -> McpLaunchServer {
        McpLaunchServer(name: serverName, command: helper, arguments: [bridgeFlag, bridgeFile])
    }

    public static func helper(inApp bundle: URL) -> URL {
        bundle.appending(path: "Contents/Helpers/\(helperName)")
    }

    public static func bridgeFileName(tab: String) -> String {
        let safe = String(tab.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" })
        return "orchestrator-bridge-\(safe.isEmpty ? "_" : safe).json"
    }
}
