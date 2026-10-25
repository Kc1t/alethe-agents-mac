import AletheAgents
import AletheOrchestrator
import Foundation
import Observation

@Observable
@MainActor
final class OrchestratorQuotaFeed {
    static let shared = OrchestratorQuotaFeed()

    private(set) var warnings: [QuotaWarning] = []
    @ObservationIgnored private var feed: FitnessFeed?
    @ObservationIgnored private var pending: Task<Void, Never>?

    func open(_ board: UUID, environment: AppEnvironment) {
        let feed = feed ?? makeFeed(environment)
        self.feed = feed
        enqueue { await feed.open(board) }
    }

    func close(_ board: UUID) {
        guard let feed else { return }
        enqueue { await feed.close(board) }
    }

    private func enqueue(_ step: @escaping @Sendable () async -> Void) {
        pending = Task { [previous = pending] in
            await previous?.value
            await step()
        }
    }

    private func makeFeed(_ environment: AppEnvironment) -> FitnessFeed {
        FitnessFeed(
            read: { await Self.read(environment) },
            push: { agent, fitness in await Self.push(agent, fitness, environment) },
            publish: { [weak self] warnings in await self?.publish(warnings) }
        )
    }

    private func publish(_ warnings: [QuotaWarning]) {
        if self.warnings != warnings { self.warnings = warnings }
    }

    private static func push(_ agent: String, _ fitness: AgentFitness, _ environment: AppEnvironment) async {
        await environment.orchestrator.prepared()?.setAgentFitness(agent, fitness)
    }

    private static func read(_ environment: AppEnvironment) async -> [ProviderUsage] {
        #if DEBUG
        if let seeded = seededUsage() { return seeded }
        #endif
        let monitor = environment.usage
        var providers: [AgentKind] = [.codex]
        if monitor.shownProviders.contains(.claude) { providers.insert(.claude, at: 0) }
        await monitor.refresh(providers)
        return [AgentKind.claude, .codex].compactMap { monitor.usage[$0] }
    }

    #if DEBUG
    private static func seededUsage() -> [ProviderUsage]? {
        guard let spec = UserDefaults.standard.string(forKey: "AletheUITestUsage") else { return nil }
        let resetsAt = Date().addingTimeInterval(2 * 3600)
        return spec.split(separator: ",").compactMap { entry in
            let parts = entry.split(separator: ":")
            guard parts.count == 2 else { return nil }
            let limited = parts[1].hasSuffix("!")
            guard let percent = Double(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "!"))) else { return nil }
            return ProviderUsage(agent: AgentKind(rawValue: String(parts[0])), status: .ready,
                                 windows: [UsageWindow(label: "5h", usedPercent: percent, resetsAt: resetsAt)],
                                 rateLimited: limited)
        }
    }
    #endif
}
