import Foundation

public struct ResourcePolicy: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case manual
        case pressure
        case idle
    }

    public var mode: Mode
    public var hiddenAgentIdleMinutes: Int
    public var hiddenShellIdleMinutes: Int
    public var spawnGraceSeconds: Int

    public init(mode: Mode = .manual, hiddenAgentIdleMinutes: Int = 15, hiddenShellIdleMinutes: Int = 30,
                spawnGraceSeconds: Int = 120) {
        self.mode = mode
        self.hiddenAgentIdleMinutes = hiddenAgentIdleMinutes
        self.hiddenShellIdleMinutes = hiddenShellIdleMinutes
        self.spawnGraceSeconds = spawnGraceSeconds
    }

    public static let agentIdleRange = 5...240
    public static let shellIdleRange = 5...480

    public var normalized: ResourcePolicy {
        var result = self
        result.hiddenAgentIdleMinutes = min(max(hiddenAgentIdleMinutes, Self.agentIdleRange.lowerBound), Self.agentIdleRange.upperBound)
        result.hiddenShellIdleMinutes = min(max(hiddenShellIdleMinutes, Self.shellIdleRange.lowerBound), Self.shellIdleRange.upperBound)
        result.spawnGraceSeconds = min(max(spawnGraceSeconds, 30), 900)
        return result
    }
}

public enum MemoryPressure: Int, Comparable, Sendable {
    case normal, warning, critical

    public static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func level(availableMB: Double, totalMB: Double, previous: MemoryPressure) -> MemoryPressure {
        let total = max(totalMB, 1)
        let critical = max(total * 0.05, 512)
        let warning = max(total * 0.10, 1024)
        if availableMB <= critical || (previous == .critical && availableMB <= critical * 1.25) { return .critical }
        if availableMB <= warning || (previous == .warning && availableMB <= warning * 1.25) { return .warning }
        return .normal
    }
}

public struct TerminalRuntime: Hashable, Sendable {
    public var tab: TabID
    public var isShell: Bool
    public var isMounted: Bool
    public var isFocused: Bool
    public var lastOutput: TimeInterval
    public var startedAt: TimeInterval
    public var lastUsed: TimeInterval
    public var memoryMB: Double

    public init(tab: TabID, isShell: Bool, isMounted: Bool, isFocused: Bool, lastOutput: TimeInterval,
                startedAt: TimeInterval, lastUsed: TimeInterval, memoryMB: Double) {
        self.tab = tab
        self.isShell = isShell
        self.isMounted = isMounted
        self.isFocused = isFocused
        self.lastOutput = lastOutput
        self.startedAt = startedAt
        self.lastUsed = lastUsed
        self.memoryMB = memoryMB
    }
}

public enum ResourceSupervision {
    public static func mayHibernate(_ level: MemoryPressure, policy: ResourcePolicy) -> Bool {
        if case .manual = policy.mode { return false }
        else if case .pressure = policy.mode { return level == .critical }
        else { return true }
    }

    public static func candidates(_ runtimes: [TerminalRuntime], policy: ResourcePolicy, now: TimeInterval) -> [TabID] {
        let policy = policy.normalized
        return runtimes
            .filter { runtime in
                guard !runtime.isMounted, !runtime.isFocused,
                      now - runtime.startedAt >= TimeInterval(policy.spawnGraceSeconds) else { return false }
                let idle = runtime.isShell ? policy.hiddenShellIdleMinutes : policy.hiddenAgentIdleMinutes
                return now - runtime.lastOutput >= TimeInterval(idle * 60)
            }
            .sorted { a, b in
                if a.isShell != b.isShell { return a.isShell }
                if a.lastUsed != b.lastUsed { return a.lastUsed < b.lastUsed }
                return a.memoryMB > b.memoryMB
            }
            .map(\.tab)
    }
}

extension WorkspaceDocument {
    public var mountedTabIDs: Set<TabID> {
        let shown = workspace.fullscreenProjectID.map { [$0] } ?? workspace.openProjectIDs
        return Set(shown.compactMap(project).flatMap(\.visiblePanes).filter { !$0.isDisabled }.compactMap(\.activeTab?.id))
    }
}
