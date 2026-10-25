import Foundation

public struct GSDSyncTarget: Hashable, Sendable {
    public var projectID: String
    public var directory: URL

    public init(projectID: String, directory: URL) {
        self.projectID = projectID
        self.directory = directory
    }
}

public struct GSDSyncSession: Hashable, Sendable, Identifiable {
    public var projectID: String
    public var root: URL
    public var childID: String
    public var busy: Bool
    public var error: String?
    public var planning: PlanningStatus

    public init(projectID: String, root: URL, childID: String, busy: Bool, error: String?, planning: PlanningStatus) {
        self.projectID = projectID
        self.root = root
        self.childID = childID
        self.busy = busy
        self.error = error
        self.planning = planning
    }

    public var id: String { "\(projectID):\(root.path)" }
    public var name: String { root.lastPathComponent }

    public var roadmapProgress: (done: Int, total: Int)? {
        guard let total = planning.roadmapTotalCount, let pending = planning.roadmapPendingCount, total > 0 else { return nil }
        return (total - pending, total)
    }
}

extension GSDSyncService {
    public func sessions(for targets: [GSDSyncTarget]) async -> [GSDSyncSession] {
        await Task.detached(priority: .utility) { Self.readSessions(targets) }.value
    }

    static func readSessions(_ targets: [GSDSyncTarget]) -> [GSDSyncSession] {
        var seen: Set<String> = []
        var sessions: [GSDSyncSession] = []
        for target in targets {
            if Task.isCancelled { break }
            guard let root = PlanningGate.repositoryRoot(containing: target.directory),
                  seen.insert("\(target.projectID):\(root.path)").inserted else { continue }
            let child = PlanningGate.childState(of: root)
            guard let childID = child.sessionID else { continue }
            sessions.append(GSDSyncSession(projectID: target.projectID, root: root, childID: childID, busy: child.busy,
                                           error: child.error, planning: PlanningGate.status(of: root)))
        }
        return sessions
    }
}
