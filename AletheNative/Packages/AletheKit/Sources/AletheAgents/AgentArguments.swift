import Foundation

public struct AgentArguments: Equatable, Sendable {
    public var arguments: [String]
    public var sessionID: String?
    public var createdSession: Bool

    public init(arguments: [String], sessionID: String? = nil, createdSession: Bool = false) {
        self.arguments = arguments
        self.sessionID = sessionID
        self.createdSession = createdSession
    }

    public static func build(
        for kind: AgentKind,
        base: [String] = [],
        sessionID: String? = nil,
        makeSessionID: () -> String = { UUID().uuidString.lowercased() }
    ) -> AgentArguments {
        if case .claude = kind {
            let clean = stripping(base, flagsWithValue: ["--resume", "-r", "--session-id"], flags: ["--continue", "-c"])
            if let sessionID {
                return AgentArguments(arguments: ["--resume", sessionID] + clean, sessionID: sessionID)
            }
            let created = makeSessionID()
            return AgentArguments(arguments: ["--session-id", created] + clean, sessionID: created, createdSession: true)
        } else if case .codex = kind {
            let clean = strippingCodexResume(base)
            return AgentArguments(arguments: sessionID.map { ["resume", $0] + clean } ?? clean, sessionID: sessionID)
        } else if case .opencode = kind {
            let clean = stripping(base, flagsWithValue: ["--session", "-s"], flags: ["--continue", "-c", "--resume"])
            return AgentArguments(arguments: sessionID.map { ["--session", $0] + clean } ?? clean, sessionID: sessionID)
        } else if case .antigravity = kind {
            let clean = stripping(base, flagsWithValue: ["--conversation"], flags: ["--continue", "-c"])
            return AgentArguments(arguments: sessionID.map { ["--conversation", $0] + clean } ?? clean, sessionID: sessionID)
        } else if case .kiro = kind {
            return AgentArguments(arguments: ["chat"] + base)
        } else if case .cursor = kind {
            let clean = stripping(base, flagsWithValue: ["--resume"], flags: ["--continue"])
                .filter { !$0.hasPrefix("--resume=") }
            return AgentArguments(arguments: sessionID.map { ["--resume", $0] + clean } ?? clean, sessionID: sessionID)
        } else {
            return AgentArguments(arguments: base)
        }
    }

    private static func stripping(_ arguments: [String], flagsWithValue: Set<String>, flags: Set<String>) -> [String] {
        var clean: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if flagsWithValue.contains(argument) {
                index += 2
                continue
            }
            if !flags.contains(argument) { clean.append(argument) }
            index += 1
        }
        return clean
    }

    private static func strippingCodexResume(_ arguments: [String]) -> [String] {
        guard arguments.first == "resume" else { return arguments }
        var rest = Array(arguments.dropFirst())
        if let first = rest.first, first == "--last" || !first.hasPrefix("-") { rest.removeFirst() }
        return rest
    }
}
