import Foundation

public enum SessionResume {
    public static let earlyExitWindow: Duration = .seconds(4)

    public static func isResumable(_ kind: AgentKind, sessionID: String, cwd: String?,
                                   homeDirectory: String = NSHomeDirectory()) -> Bool {
        switch kind {
        case .claude:
            return ClaudeTranscripts.exists(sessionID: sessionID, homeDirectory: homeDirectory)
        case .codex:
            guard let cwd else { return false }
            return CodexSessions.snapshot(cwd: cwd, homeDirectory: homeDirectory).contains { $0.id == sessionID }
        case .antigravity:
            return AntigravitySessions.snapshot(cwd: "", homeDirectory: homeDirectory).contains { $0.id == sessionID }
        default:
            return true
        }
    }

    public static func discoversNewSessions(_ kind: AgentKind) -> Bool {
        kind == .codex || kind == .opencode || kind == .antigravity
    }

    public static func snapshot(_ kind: AgentKind, cwd: String, executable: String?) async -> [SessionSnapshot] {
        switch kind {
        case .codex: return CodexSessions.snapshot(cwd: cwd)
        case .antigravity: return AntigravitySessions.snapshot(cwd: cwd)
        case .opencode:
            guard let executable else { return [] }
            return await OpenCodeSessions.snapshot(cwd: cwd, executable: executable)
        default: return []
        }
    }

    public static func shouldRetryFresh(resumed: Bool, elapsed: Duration, alreadyRetried: Bool) -> Bool {
        resumed && !alreadyRetried && elapsed < earlyExitWindow
    }

    public static func discoveryDelay(attempt: Int) -> Duration {
        attempt < 10 ? .seconds(3) : .seconds(15)
    }

    public static func discover(isolation: isolated (any Actor)? = #isolation,
                                sleep: (Duration) async -> Void,
                                attempt: () async -> String?) async -> String? {
        var index = 0
        while !Task.isCancelled {
            await sleep(discoveryDelay(attempt: index))
            if Task.isCancelled { return nil }
            if let id = await attempt() { return id }
            index += 1
        }
        return nil
    }

    public static func previous(in sessions: [SessionSnapshot], excluding current: String?, before: Date?) -> String? {
        let candidates = sessions.filter { $0.id != current }
        let older = before.map { date in candidates.filter { $0.modifiedAt < date } } ?? []
        return (older.isEmpty ? candidates : older).max { $0.modifiedAt < $1.modifiedAt }?.id
    }

    public static func sessions(_ kind: AgentKind, cwd: String) -> [SessionSnapshot] {
        switch kind {
        case .claude: ClaudeSessions.snapshot(cwd: cwd)
        case .codex: CodexSessions.snapshot(cwd: cwd)
        case .antigravity: AntigravitySessions.snapshot(cwd: cwd)
        default: []
        }
    }
}
