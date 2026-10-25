import AletheIntegrations
import Foundation

public enum RunLane: String, Hashable, Sendable, CaseIterable {
    case blocked
    case running
    case queued
    case interrupted
    case failed
    case finished

    private static let lanes: [JobStatus: RunLane] = [
        .blocked: .blocked, .running: .running, .queued: .queued, .interrupted: .interrupted, .failed: .failed,
    ]

    public init(_ status: JobStatus) {
        self = Self.lanes[status] ?? .finished
    }

    static let statePriority: [RunLane] = [.blocked, .failed, .interrupted, .running, .queued, .finished]
}

public struct RunCounts: Hashable, Sendable {
    public private(set) var values: [RunLane: Int]

    public init(_ values: [RunLane: Int] = [:]) {
        self.values = values.filter { $0.value != 0 }
    }

    public init(jobs: some Sequence<JobSnapshot>) {
        var counts = RunCounts()
        for job in jobs { counts[RunLane(job.status)] += 1 }
        self = counts
    }

    public subscript(lane: RunLane) -> Int {
        get { values[lane] ?? 0 }
        set { values[lane] = newValue == 0 ? nil : newValue }
    }

    public var total: Int { values.values.reduce(0, +) }

    public var worstState: RunLane {
        RunLane.statePriority.first { self[$0] > 0 } ?? .finished
    }

    public var attention: RunAttention? {
        RunAttention.Lane.allCases.first { self[$0.runLane] > 0 }.map { RunAttention(lane: $0, count: self[$0.runLane]) }
    }
}

public struct RunAttention: Hashable, Sendable {
    public enum Lane: String, Hashable, Sendable, CaseIterable {
        case blocked
        case failed
        case interrupted

        public var runLane: RunLane {
            RunLane(rawValue: rawValue) ?? .interrupted
        }
    }

    public var lane: Lane
    public var count: Int

    public init(lane: Lane, count: Int) {
        self.lane = lane
        self.count = count
    }
}

public struct BoardRun: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var jobs: [JobSnapshot]
    public var counts: RunCounts
    public var state: RunLane

    public init(id: String, label: String, jobs: [JobSnapshot]) {
        self.id = id
        self.label = label
        self.jobs = jobs
        counts = RunCounts(jobs: jobs)
        state = counts.worstState
    }

    public static func group(_ jobs: [JobSnapshot]) -> [BoardRun] {
        var order: [String] = []
        var grouped: [String: [JobSnapshot]] = [:]
        for job in jobs {
            if grouped[job.runID] == nil { order.append(job.runID) }
            grouped[job.runID, default: []].append(job)
        }
        return order.map { runID in
            let runJobs = grouped[runID] ?? []
            let label = runJobs.lazy.compactMap { cleaned($0.runLabel) }.first
            return BoardRun(id: runID, label: label ?? runID, jobs: runJobs)
        }
    }
}

public struct PlannerGroup: Hashable, Sendable {
    public var id: String?
    public var label: String?
    public var agent: String?
    public var runs: [BoardRun]
    public var jobs: [JobSnapshot]
    public var counts: RunCounts
    public var state: RunLane

    public init(id: String?, label: String?, agent: String?, jobs: [JobSnapshot]) {
        self.id = id
        self.label = label
        self.agent = agent
        self.jobs = jobs
        runs = BoardRun.group(jobs)
        counts = RunCounts(jobs: jobs)
        state = counts.worstState
    }

    public static func group(jobs: [JobSnapshot], planners: [Planner]) -> [PlannerGroup] {
        var order: [String?] = []
        var buckets: [String?: [JobSnapshot]] = [:]
        for job in jobs {
            if buckets[job.plannerID] == nil { order.append(job.plannerID) }
            buckets[job.plannerID, default: []].append(job)
        }

        let declared = planners.sorted { lhs, rhs in
            let byLabel = collate(lhs.label, rhs.label)
            return byLabel == .orderedSame ? collate(lhs.id, rhs.id) == .orderedAscending : byLabel == .orderedAscending
        }
        var groups = declared.map { planner in
            PlannerGroup(
                id: planner.id,
                label: cleaned(planner.label) ?? planner.id,
                agent: cleaned(planner.agent),
                jobs: buckets[planner.id] ?? []
            )
        }

        let known = Set(planners.map(\.id))
        for case let key? in order where !known.contains(key) {
            groups.append(PlannerGroup(id: key, label: key, agent: nil, jobs: buckets[key] ?? []))
        }
        if let orphans = buckets[nil] {
            groups.append(PlannerGroup(id: nil, label: nil, agent: nil, jobs: orphans))
        }
        return groups
    }

    private static func collate(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, locale: Locale(identifier: "en_US_POSIX"))
    }
}

public struct AgentSpend: Hashable, Sendable {
    public var agent: String
    public var totalTokens: Double
    public var costUSD: Double
    public var pricedWorkers: Int
    public var unpricedWorkers: Int

    public init(agent: String, totalTokens: Double = 0, costUSD: Double = 0, pricedWorkers: Int = 0, unpricedWorkers: Int = 0) {
        self.agent = agent
        self.totalTokens = totalTokens
        self.costUSD = costUSD
        self.pricedWorkers = pricedWorkers
        self.unpricedWorkers = unpricedWorkers
    }

    public static func aggregate(_ jobs: [JobSnapshot]) -> [AgentSpend] {
        var order: [String] = []
        var byAgent: [String: AgentSpend] = [:]
        for job in jobs {
            let totalTokens = BoardFormat.totalTokens(job) ?? 0
            if totalTokens <= 0 && job.costUSD == nil { continue }
            var current = byAgent[job.agent] ?? AgentSpend(agent: job.agent)
            if byAgent[job.agent] == nil { order.append(job.agent) }
            current.totalTokens += totalTokens
            if let cost = job.costUSD {
                current.costUSD += cost
                current.pricedWorkers += 1
            } else {
                current.unpricedWorkers += 1
            }
            byAgent[job.agent] = current
        }
        return order.compactMap { byAgent[$0] }
    }
}

func cleaned(_ value: String?) -> String? {
    let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
