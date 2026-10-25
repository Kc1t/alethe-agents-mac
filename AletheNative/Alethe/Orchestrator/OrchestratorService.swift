import AletheAgents
import AletheFoundation
import AletheIntegrations
import AletheModel
import AletheOrchestrator
import Foundation
import Observation

@Observable
@MainActor
final class OrchestratorService {
    private(set) var snapshot = OrchestratorSnapshot()
    private(set) var isPrepared = false
    private var workerRules: [WorkerRuleSet]? = []
    private var settings = OrchestrationPreferences()

    @ObservationIgnored private var setup: Setup?
    @ObservationIgnored private var isEnabled: @MainActor () -> Bool = { false }
    @ObservationIgnored private var leftovers: Task<Void, Never>?
    @ObservationIgnored private var preparing: Task<OrchestratorCore?, Never>?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var isShutDown = false

    private struct Setup {
        var profileDirectory: URL
        var registry: WorkerRegistry
        var launchers: LauncherCache
        var overrides: @MainActor () -> [String: String]
    }

    func start(profileDirectory: URL, launchers: LauncherCache,
               overrides: @escaping @MainActor () -> [String: String],
               isEnabled: @escaping @MainActor () -> Bool) {
        guard setup == nil else { return }
        let registry = WorkerRegistry(profileDirectory: profileDirectory)
        setup = Setup(profileDirectory: profileDirectory, registry: registry, launchers: launchers, overrides: overrides)
        self.isEnabled = isEnabled
        leftovers = Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: registry.url.path) else { return }
            _ = await registry.terminateLeftovers()
        }
    }

    func prepared() async -> OrchestratorCore? {
        if let preparing { return await preparing.value }
        guard let setup, !isShutDown else { return nil }
        let overrides = setup.overrides()
        let leftovers = leftovers
        let (cache, registry, profileDirectory) = (setup.launchers, setup.registry, setup.profileDirectory)
        let task = Task { [weak self] () -> OrchestratorCore? in
            let core = await Task.detached(priority: .userInitiated) { () -> OrchestratorCore in
                await leftovers?.value
                let launchers = WorkerLaunchers.resolve { cache.resolve($0, override: overrides[$0]) }
                let directories = cache.searchDirectories
                let core = OrchestratorCore(configuration: OrchestratorCore.Configuration(
                    launchers: launchers,
                    store: OrchestratorJobStore(profileDirectory: profileDirectory),
                    registry: registry,
                    environment: { WorkerEnvironment.make(for: $0, searchDirectories: directories) }
                ))
                await core.restore()
                return core
            }.value
            if let self {
                await core.applySettings(self.settings)
                await core.applyWorkerRules(self.workerRules)
            }
            self?.observe(core)
            return core
        }
        preparing = task
        return await task.value
    }

    private func observe(_ core: OrchestratorCore) {
        isPrepared = true
        guard !isShutDown else { return }
        observation = Task { [weak self] in
            for await snapshot in await core.snapshots() {
                guard let self else { return }
                self.snapshot = snapshot
            }
        }
    }

    func registerPlanner(_ planner: Planner) {
        Task { await prepared()?.registerPlanner(planner) }
    }

    nonisolated func handleMcp(body: Data, planner: String?) async -> AgentHookServer.McpReply {
        guard let core = await coreIfEnabled() else { return .unavailable }
        guard let reply = await OrchestratorMCP.handle(body: body, planner: planner, handler: core) else { return .accepted }
        return .body(reply)
    }

    private func coreIfEnabled() async -> OrchestratorCore? {
        guard isEnabled() else { return nil }
        return await prepared()
    }

    func answer(job: String, decision: String) async throws -> OrderedJSON {
        try await callTool("alethe_answer", ["jobId": .string(job), "decision": .string(decision)])
    }

    func diff(job: String) async -> String? {
        guard let core = await prepared(), let found = await core.job(job) else { return nil }
        return found.diff ?? ""
    }

    func message(job: String, text: String, steer: Bool) async throws -> OrderedJSON {
        try await callTool(steer ? "alethe_steer" : "alethe_send", ["jobId": .string(job), "message": .string(text)])
    }

    func applyWorkerRules(_ value: [WorkerRuleSet]?) async {
        workerRules = value
        if let preparing, let core = await preparing.value { await core.applyWorkerRules(value) }
    }

    func applySettings(_ value: OrchestrationPreferences) async {
        settings = value.normalized
        if let preparing, let core = await preparing.value { await core.applySettings(settings) }
    }

    func setConcurrencyLimit(_ limit: Int) async {
        await prepared()?.setConcurrencyLimit(limit)
    }

    private func callTool(_ name: String, _ arguments: OrderedJSONObject) async throws -> OrderedJSON {
        guard let core = await prepared() else { throw OrchestratorToolError("the orchestrator is not running") }
        return try await core.callTool(name: name, arguments: arguments, planner: nil)
    }

    func shutdown() async {
        isShutDown = true
        if let preparing, let core = await preparing.value {
            await core.shutdown()
        }
        observation?.cancel()
        observation = nil
        await leftovers?.value
    }
}
