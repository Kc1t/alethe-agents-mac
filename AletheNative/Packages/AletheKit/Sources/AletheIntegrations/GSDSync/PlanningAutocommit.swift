import AletheFoundation
import Foundation

public struct DebounceGenerations: Sendable {
    private var latest: [String: UInt64] = [:]

    public init() {}

    public mutating func bump(_ key: String) -> UInt64 {
        let next = (latest[key] ?? 0) &+ 1
        latest[key] = next
        return next
    }

    public func isLatest(_ generation: UInt64, for key: String) -> Bool {
        latest[key] == generation
    }
}

public actor PlanningAutocommit {
    public typealias Commit = @Sendable (_ root: URL, _ projectID: String?) async -> Void

    public static let defaultDelay: Duration = .seconds(2)

    public private(set) var isEnabled = false
    private let bus: EventBus
    private let delay: Duration
    private let commit: Commit
    private var generations = DebounceGenerations()
    private var loop: Task<Void, Never>?
    private var pending: [String: Task<Void, Never>] = [:]

    public init(bus: EventBus, delay: Duration = defaultDelay, commit: @escaping Commit) {
        self.bus = bus
        self.delay = delay
        self.commit = commit
    }

    public init(bus: EventBus, audit: PlanningAudit, delay: Duration = defaultDelay) {
        self.init(bus: bus, delay: delay) { root, projectID in
            do {
                try await audit.record(repository: root, reason: "auto-commit", projectID: projectID)
            } catch {
                AppLog.record(.warning, .integrations, "Planning auto-commit failed: \(error)")
            }
        }
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { cancelPending() }
    }

    public func start() async {
        guard loop == nil else { return }
        let events = await bus.subscribe()
        loop = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        cancelPending()
    }

    func handle(_ event: BusEvent) {
        guard event.type == BusEventType.planningUpdated, isEnabled,
              let planningDir = event.data.objectValue?["planning_dir"]?.stringValue else { return }
        let generation = generations.bump(planningDir)
        let projectID = event.taskID
        let delay = delay
        pending[planningDir]?.cancel()
        pending[planningDir] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.fire(planningDir: planningDir, generation: generation, projectID: projectID)
        }
    }

    private func fire(planningDir: String, generation: UInt64, projectID: String?) async {
        guard isEnabled, generations.isLatest(generation, for: planningDir) else { return }
        pending[planningDir] = nil
        let root = URL(filePath: planningDir, directoryHint: .isDirectory).deletingLastPathComponent()
        await commit(root, projectID)
    }

    private func cancelPending() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
    }
}
