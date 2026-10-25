import AletheFoundation
import AletheGit
import AletheIntegrations
import AletheModel
import Darwin
import Foundation

public actor OrchestratorCore {
    public struct Configuration: Sendable {
        public var launchers: WorkerLaunchers
        public var concurrencyLimit: Int
        public var store: OrchestratorJobStore?
        public var registry: WorkerRegistry?
        public var environment: @Sendable (Launcher) -> [String: String]
        public var uncommittedDiff: @Sendable (_ cwd: String) async -> String?
        public var terminationGrace: Duration
        public var worktrees: GitWorktrees

        public init(
            launchers: WorkerLaunchers = WorkerLaunchers(),
            concurrencyLimit: Int = OrchestratorLimits.defaultConcurrency,
            store: OrchestratorJobStore? = nil,
            registry: WorkerRegistry? = nil,
            environment: @escaping @Sendable (Launcher) -> [String: String] = OrchestratorCore.defaultEnvironment,
            uncommittedDiff: @escaping @Sendable (String) async -> String? = { await ClaudeWorkerProtocol.uncommittedDiff(in: $0) },
            terminationGrace: Duration = WorkerProcess.terminationGrace,
            worktrees: GitWorktrees = GitWorktrees()
        ) {
            self.launchers = launchers
            self.concurrencyLimit = concurrencyLimit
            self.store = store
            self.registry = registry
            self.environment = environment
            self.uncommittedDiff = uncommittedDiff
            self.terminationGrace = terminationGrace
            self.worktrees = worktrees
        }
    }

    public static let defaultEnvironment: @Sendable (Launcher) -> [String: String] = { launcher in
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return WorkerEnvironment.make(for: launcher, searchDirectories: path.split(separator: ":").map(String.init))
    }

    struct WorkerHandle {
        let process: WorkerProcess
        let generation: UInt64
        var codex: CodexWorkerSession?
        var pump: Task<Void, Never>?
        var watchdog: Task<Void, Never>?
    }

    var workerRuleSets: [WorkerRuleSet] = []
    var orchestrationSettings = OrchestrationPreferences()
    var configuration: Configuration
    var launchers: WorkerLaunchers
    var jobs: [String: Job] = [:]
    var order: [String] = []
    var queue: [String] = []
    var slots: Set<String> = []
    var deliveries: [Delivery] = []
    var deliverySequence: UInt64 = 0
    var concurrencyLimit: Int
    var jobCounter: UInt64 = 0
    var runCounter: UInt64 = 0
    var planners: [Planner] = []
    var workers: [String: WorkerHandle] = [:]
    var spawning: [String: UInt64] = [:]
    var spawnTasks: [UInt64: Task<Void, Never>] = [:]
    var generationCounter: UInt64 = 0
    var terminations: [UInt64: Task<Void, Never>] = [:]
    var terminationCounter: UInt64 = 0
    var isShutDown = false
    var fitnessReadings: [String: AgentFitness] = [:]
    var deferredPrompts: PromptQueue?

    private var observers: [UInt64: AsyncStream<OrchestratorSnapshot>.Continuation] = [:]
    private var observerCounter: UInt64 = 0
    private var changeWaiters: [UInt64: CheckedContinuation<Void, Never>] = [:]
    private var waiterCounter: UInt64 = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.launchers = configuration.launchers
        self.concurrencyLimit = Self.clampedLimit(configuration.concurrencyLimit)
    }

    static func clampedLimit(_ limit: Int) -> Int {
        min(max(limit, OrchestratorLimits.concurrencyRange.lowerBound), OrchestratorLimits.concurrencyRange.upperBound)
    }

    static func nowMs() -> UInt64 { CodexWorkerSession.currentMilliseconds() }

    @discardableResult
    public func restore() -> OrchestratorRestore.Outcome? {
        guard let store = configuration.store else { return nil }
        let restored = store.restore()
        for job in restored.jobs where jobs[job.id] == nil {
            jobs[job.id] = job
            order.append(job.id)
        }
        for planner in restored.planners { upsert(planner) }
        jobCounter = max(jobCounter, restored.jobCounter)
        runCounter = max(runCounter, restored.runCounter)
        let prompts = promptQueue()
        Task { await prompts.tick() }
        notify()
        return restored.outcome
    }

    public func registerPlanner(_ planner: Planner) {
        upsert(planner)
        notify()
        persist()
    }

    public func setLauncher(_ launcher: Launcher) {
        launchers.set(launcher)
    }

    public func setLaunchers(_ launchers: WorkerLaunchers) {
        self.launchers = launchers
    }

    public func setConcurrencyLimit(_ limit: Int) {
        concurrencyLimit = Self.clampedLimit(limit)
        notify()
        drainQueue()
    }

    private func upsert(_ planner: Planner) {
        if let index = planners.firstIndex(where: { $0.id == planner.id }) {
            planners[index] = planner
        } else {
            planners.append(planner)
        }
    }

    public func snapshot() -> OrchestratorSnapshot {
        let now = Self.nowMs()
        return OrchestratorSnapshot(
            jobs: order.compactMap { jobs[$0]?.snapshot(nowMs: now) },
            planners: planners,
            running: slots.count,
            queued: queue.count,
            concurrencyLimit: concurrencyLimit
        )
    }

    public func counts() -> (running: Int, queued: Int) {
        (slots.count, queue.count)
    }

    public func job(_ id: String) -> Job? { jobs[id] }

    public func snapshots(
        bufferingPolicy: AsyncStream<OrchestratorSnapshot>.Continuation.BufferingPolicy = .bufferingNewest(64)
    ) -> AsyncStream<OrchestratorSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: OrchestratorSnapshot.self, bufferingPolicy: bufferingPolicy)
        observerCounter += 1
        let id = observerCounter
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        continuation.yield(snapshot())
        return stream
    }

    private func removeObserver(_ id: UInt64) {
        observers[id] = nil
    }

    func notify() {
        if let deferredPrompts { Task { await deferredPrompts.tick() } }
        guard !observers.isEmpty else { return }
        let current = snapshot()
        for continuation in observers.values { continuation.yield(current) }
    }

    func persist() {
        configuration.store?.persist(jobs: order.compactMap { jobs[$0] }, planners: planners)
    }

    func pushDelivery(kind: String, jobID: String, outcome: String?, text: String) {
        deliverySequence += 1
        deliveries.append(Delivery(sequence: deliverySequence, kind: kind, jobID: jobID, outcome: outcome, text: text))
    }

    func signal() {
        let waiting = changeWaiters
        changeWaiters.removeAll()
        for continuation in waiting.values { continuation.resume() }
    }

    func waitForChange(until deadline: ContinuousClock.Instant) async {
        waiterCounter += 1
        let id = waiterCounter
        let timer = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            await self?.resumeWaiter(id)
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    changeWaiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.resumeWaiter(id) }
        }
        timer.cancel()
    }

    private func resumeWaiter(_ id: UInt64) {
        changeWaiters.removeValue(forKey: id)?.resume()
    }

    func drainQueue() {
        while !isShutDown, slots.count < concurrencyLimit, !queue.isEmpty {
            let jobID = queue.removeFirst()
            guard jobs[jobID]?.status == .queued else { continue }
            spawnWorker(jobID)
        }
    }

    private func releaseOldestParked() {
        var parked = parkedJobIDs
        while parked.count > OrchestratorLimits.parkedLimit {
            let oldest = parked.removeFirst()
            teardownWorker(oldest)
            jobs[oldest]?.status = .released
        }
    }

    func finishTurn(
        _ jobID: String,
        status: JobStatus,
        outcome: String?,
        text: String,
        terminal: Bool,
        announce: Bool = true
    ) {
        guard var job = jobs[jobID], !job.settled else { return }
        job.status = status
        if status == .failed, QueueLimit.detected(in: text + "\n" + job.reply) {
            var fitness = fitnessReadings[job.agent] ?? AgentFitness(worst: "limit", used: 100)
            fitness.rateLimited = true
            fitness.resetsAt = QueueLimit.reset(in: text + "\n" + job.reply) ?? fitness.resetsAt.flatMap { $0 > Date() ? $0 : nil }
            fitnessReadings[job.agent] = fitness
        }
        job.pending = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { job.report = trimmed }
        job.outcome = outcome
        job.endedAt = Self.nowMs()
        job.activeTurnID = nil
        jobs[jobID] = job
        queue.removeAll { $0 == jobID }
        slots.remove(jobID)
        if terminal { teardownWorker(jobID) }
        if announce { pushDelivery(kind: "worker_done", jobID: jobID, outcome: outcome, text: text) }

        if !terminal, !isShutDown, let next = nextTurnFromInbox(jobID) {
            jobs[jobID]?.status = .running
            jobs[jobID]?.outcome = nil
            jobs[jobID]?.endedAt = nil
            jobs[jobID]?.reply = ""
            jobs[jobID]?.report = ""
            slots.insert(jobID)
            writeToWorker(jobID, next)
        } else {
            releaseOldestParked()
        }
        notify()
        persist()
        signal()
        drainQueue()
    }

    func nextTurnFromInbox(_ jobID: String) -> OrderedJSON? {
        guard var job = jobs[jobID], workers[jobID] != nil, job.threadID != nil, !job.inbox.isEmpty else { return nil }
        if job.agent == WorkerAgent.claude {
            let turn = ClaudeWorkerProtocol.nextTurn(&job)
            jobs[jobID] = job
            return turn
        }
        guard var session = workers[jobID]?.codex else { return nil }
        let text = job.inbox.removeFirst()
        guard let turn = try? session.startTurn(text) else { return nil }
        job.nextRequestID = session.nextRequestID
        jobs[jobID] = job
        workers[jobID]?.codex = session
        return turn
    }

    public func shutdown() async {
        isShutDown = true
        await deferredPrompts?.shutdown()
        for jobID in queue { jobs[jobID]?.status = .interrupted }
        queue.removeAll()
        let live = Set(workers.keys).union(spawning.keys).union(slots)
        for jobID in live {
            teardownWorker(jobID)
            if let job = jobs[jobID], !job.settled {
                jobs[jobID]?.status = .interrupted
                jobs[jobID]?.pending = nil
                jobs[jobID]?.activeTurnID = nil
            }
        }
        slots.removeAll()
        notify()
        persist()
        signal()
        while let (key, spawn) = spawnTasks.first {
            await spawn.value
            spawnTasks[key] = nil
        }
        while let (key, termination) = terminations.first {
            await termination.value
            terminations[key] = nil
        }
        await configuration.store?.flush()
    }

    public var workerPIDs: [pid_t] { workers.values.map(\.process.pid) }
}
