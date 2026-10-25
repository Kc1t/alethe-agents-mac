import AletheAgents
import Foundation

public struct QuotaWarning: Hashable, Sendable {
    public var agent: String
    public var used: Int
    public var resetsAt: Date?
    public var rateLimited: Bool

    public init(agent: String, used: Int, resetsAt: Date? = nil, rateLimited: Bool = false) {
        self.agent = agent
        self.used = used
        self.resetsAt = resetsAt
        self.rateLimited = rateLimited
    }

    public init?(agent: String, fitness: AgentFitness) {
        guard fitness.isStrained else { return nil }
        self.init(agent: agent, used: fitness.used, resetsAt: fitness.resetsAt, rateLimited: fitness.rateLimited)
    }

    public static func warnings(_ readings: [String: AgentFitness]) -> [QuotaWarning] {
        FitnessRouting(readings).entries.compactMap { QuotaWarning(agent: $0.agent, fitness: $0.fitness) }
    }

    public static func countdown(to resetsAt: Date, now: Date = Date()) -> String? {
        let milliseconds = (resetsAt.timeIntervalSince(now) * 1000).rounded(.down)
        guard milliseconds > 0 else { return nil }
        let hours = Int(milliseconds / 3_600_000)
        let minutes = Int(milliseconds.truncatingRemainder(dividingBy: 3_600_000) / 60_000)
        return hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
    }
}

public actor FitnessFeed {
    public typealias Read = @Sendable () async -> [ProviderUsage]
    public typealias Push = @Sendable (_ agent: String, _ fitness: AgentFitness) async -> Void
    public typealias Publish = @Sendable ([QuotaWarning]) async -> Void

    public static let defaultInterval: Duration = .seconds(60)

    private let interval: Duration
    private let read: Read
    private let push: Push
    private let publish: Publish
    private var boards: Set<UUID> = []
    private var loop: Task<Void, Never>?
    private var readings: [String: AgentFitness] = [:]

    public init(interval: Duration = FitnessFeed.defaultInterval, read: @escaping Read,
                push: @escaping Push, publish: @escaping Publish) {
        self.interval = interval
        self.read = read
        self.push = push
        self.publish = publish
    }

    public var isRunning: Bool { loop != nil }
    public var openBoards: Int { boards.count }

    public func open(_ board: UUID) {
        boards.insert(board)
        guard loop == nil else { return }
        let interval = interval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func close(_ board: UUID) {
        boards.remove(board)
        guard boards.isEmpty else { return }
        loop?.cancel()
        loop = nil
    }

    func tick() async {
        let usages = await read()
        guard !Task.isCancelled else { return }
        for usage in usages {
            guard let fitness = AgentFitness(usage) else { continue }
            readings[usage.agent.rawValue] = fitness
            await push(usage.agent.rawValue, fitness)
        }
        await publish(QuotaWarning.warnings(readings))
    }
}
