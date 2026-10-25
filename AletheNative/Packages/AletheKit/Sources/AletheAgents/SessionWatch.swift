import Foundation

public struct SessionWatch: Sendable {
    private var previous: [String: Date]?
    private var currentID: String?

    public init() {}

    public mutating func reconcile(sessions: [SessionSnapshot], currentID: String?,
                                   startedAt: Date, claimedByOthers: Set<String>) -> String? {
        let snapshot = Dictionary(sessions.map { ($0.id, $0.modifiedAt) }, uniquingKeysWith: max)
        defer { previous = snapshot; self.currentID = currentID }
        if previous != nil, self.currentID != currentID { return nil }
        let changed = sessions.filter { session in
            guard session.id != currentID, !claimedByOthers.contains(session.id),
                  session.modifiedAt >= startedAt else { return false }
            guard let previous else { return true }
            return previous[session.id].map { session.modifiedAt > $0 } ?? true
        }
        guard changed.count == 1 else { return nil }
        return changed.first?.id
    }

    public static func snapshot(_ kind: AgentKind, cwd: String, executable: String? = nil,
                                homeDirectory: String = NSHomeDirectory()) async -> [SessionSnapshot] {
        if case .claude = kind {
            return ClaudeSessions.snapshot(cwd: cwd, homeDirectory: homeDirectory)
        } else if case .codex = kind {
            return CodexSessions.snapshot(cwd: cwd, homeDirectory: homeDirectory)
        } else if case .antigravity = kind {
            return AntigravitySessions.snapshot(cwd: cwd, homeDirectory: homeDirectory)
        } else if case .opencode = kind {
            guard let executable else { return [] }
            return await OpenCodeSessions.snapshot(cwd: cwd, executable: executable)
        } else {
            return []
        }
    }
}
