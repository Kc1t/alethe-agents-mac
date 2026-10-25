import Foundation

public enum SessionResume {
    public static let earlyExitWindow: Duration = .seconds(4)

    public static func isResumable(_ kind: AgentKind, sessionID: String, cwd: String?,
                                   homeDirectory: String = NSHomeDirectory()) -> Bool {
        if case .claude = kind {
            return ClaudeTranscripts.exists(sessionID: sessionID, homeDirectory: homeDirectory)
        } else if case .codex = kind {
            guard let cwd else { return false }
            return CodexSessions.snapshot(cwd: cwd, homeDirectory: homeDirectory).contains { $0.id == sessionID }
        } else if case .antigravity = kind {
            return AntigravitySessions.snapshot(cwd: "", homeDirectory: homeDirectory).contains { $0.id == sessionID }
        } else {
            return true
        }
    }

    public static func discoversNewSessions(_ kind: AgentKind) -> Bool {
        kind == .codex || kind == .opencode || kind == .antigravity
    }

    public static func snapshot(_ kind: AgentKind, cwd: String, executable: String?) async -> [SessionSnapshot] {
        if case .codex = kind {
            return CodexSessions.snapshot(cwd: cwd)
        } else if case .antigravity = kind {
            return AntigravitySessions.snapshot(cwd: cwd)
        } else if case .opencode = kind {
            guard let executable else { return [] }
            return await OpenCodeSessions.snapshot(cwd: cwd, executable: executable)
        } else {
            return []
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
        if case .claude = kind {
            return ClaudeSessions.snapshot(cwd: cwd)
        } else if case .codex = kind {
            return CodexSessions.snapshot(cwd: cwd)
        } else if case .antigravity = kind {
            return AntigravitySessions.snapshot(cwd: cwd)
        } else {
            return []
        }
    }
}
