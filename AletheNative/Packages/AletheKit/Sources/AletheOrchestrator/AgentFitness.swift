import Foundation
import AletheAgents
import AletheIntegrations

public struct AgentFitness: Hashable, Sendable {
    public var windows: [String: Int] = [:]
    public var worst: String
    public var used: Int
    public var resetsAt: Date?
    public var plan: String?
    public var rateLimited: Bool

    public init(worst: String, used: Int, resetsAt: Date? = nil, plan: String? = nil, rateLimited: Bool = false) {
        self.worst = worst
        self.used = used
        self.resetsAt = resetsAt
        self.plan = plan
        self.rateLimited = rateLimited
    }

    public init?(_ usage: ProviderUsage) {
        guard usage.status == .ready, var worst = usage.windows.first else { return nil }
        for window in usage.windows.dropFirst() where window.usedPercent > worst.usedPercent { worst = window }
        let isCodex = usage.agent == .codex
        self.init(
            worst: Self.windowName(worst.label),
            used: Int(worst.usedPercent.rounded(.toNearestOrAwayFromZero)),
            resetsAt: worst.resetsAt,
            plan: isCodex ? usage.plan.flatMap { $0.isEmpty ? nil : $0 } : nil,
            rateLimited: isCodex && usage.rateLimited
        )
        windows = Dictionary(usage.windows.map { (Self.windowName($0.label), Int($0.usedPercent.rounded())) }, uniquingKeysWith: max)
    }

    static func windowName(_ label: String) -> String {
        switch label {
        case "7d": "week"
        case "7d Opus": "opus"
        default: label
        }
    }

    public var strain: Double { rateLimited ? .greatestFiniteMagnitude : Double(used) }

    public var isStrained: Bool { strain >= Self.headroomThreshold }

    public static let headroomThreshold: Double = 80

    public var json: OrderedJSON {
        var object: OrderedJSONObject = [
            "worst": .string(worst),
            "used": .integer(used),
            "resetsAt": resetsAt.map { .string(Self.isoFormat.format($0)) } ?? .null,
        ]
        if let plan { object["plan"] = .string(plan) }
        object["rateLimited"] = .bool(rateLimited)
        return .object(object)
    }

    private static let isoFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

public struct FitnessRouting: Sendable {
    public let entries: [(agent: String, fitness: AgentFitness)]

    public init(_ readings: [String: AgentFitness]) {
        entries = readings.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    public func fitness(of agent: String) -> AgentFitness? {
        entries.first { $0.agent == agent }?.fitness
    }

    public var headroom: String? {
        var best: (agent: String, strain: Double)?
        for entry in entries where best.map({ entry.fitness.strain < $0.strain }) ?? true {
            best = (entry.agent, entry.fitness.strain)
        }
        return best?.agent
    }

    public var mostStrained: (agent: String, fitness: AgentFitness)? {
        var worst: (agent: String, fitness: AgentFitness)?
        for entry in entries where entry.fitness.isStrained {
            if worst.map({ entry.fitness.strain >= $0.fitness.strain }) ?? true { worst = entry }
        }
        return worst
    }

    public var block: OrderedJSON? {
        guard !entries.isEmpty else { return nil }
        var object = OrderedJSONObject()
        for entry in entries { object[entry.agent] = entry.fitness.json }
        if let headroom { object["headroom"] = .string(headroom) }
        return .object(object)
    }

    public func routingNote(requested: String) -> OrderedJSON? {
        guard let strained = mostStrained else { return nil }
        return [
            "verdict": requested == strained.agent ? "ignored" : "chosen",
            "agent": .string(strained.agent),
            "window": .string(strained.fitness.worst),
            "used": .double(Double(strained.fitness.used)),
        ]
    }

    public func headroomHint(requested: String) -> OrderedJSON? {
        guard let here = fitness(of: requested), here.isStrained,
              let other = headroom, other != requested,
              let there = fitness(of: other)
        else { return nil }
        let situation = here.rateLimited
            ? "\(requested) is rate-limited right now"
            : "\(requested) is at \(here.used)% of its \(here.worst) window"
        let bothStrained = there.isStrained
        let reason = bothStrained
            ? "\(situation), and \(other) is at \(there.used)% — both are running out; \(other) has the most room left"
            : "\(situation); \(other) is at \(there.used)%"
        return [
            "agent": .string(other),
            "bothStrained": .bool(bothStrained),
            "reason": .string(reason),
        ]
    }
}
