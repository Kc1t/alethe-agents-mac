import AletheFoundation
import AletheGit
import AletheIntegrations
import Foundation

public enum SchedulerTaskStatus: String, Hashable, Sendable, CaseIterable, Codable {
    case pending, ready, running, completed, failed, blocked

    var survivesReload: Bool { self == .running || self == .completed || self == .failed }
}

public struct SchedulerTask: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var projectID: String
    public var title: String
    public var dependencies: [String]
    public var status: SchedulerTaskStatus
    public var assignedAgentID: String?
    public var leaseResource: String?
    public var worktreePath: String?
    public var priority: Int

    public init(id: String, projectID: String, title: String, dependencies: [String] = [],
                status: SchedulerTaskStatus = .pending, assignedAgentID: String? = nil,
                leaseResource: String? = nil, worktreePath: String? = nil, priority: Int = 0) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.dependencies = dependencies
        self.status = status
        self.assignedAgentID = assignedAgentID
        self.leaseResource = leaseResource
        self.worktreePath = worktreePath
        self.priority = priority
    }

    enum CodingKeys: String, CodingKey {
        case id, projectID = "projectId", title, dependencies, status
        case assignedAgentID = "assignedAgentId", leaseResource, worktreePath, priority
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(title, forKey: .title)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(status, forKey: .status)
        try container.encode(assignedAgentID, forKey: .assignedAgentID)
        try container.encode(leaseResource, forKey: .leaseResource)
        try container.encode(worktreePath, forKey: .worktreePath)
        try container.encode(priority, forKey: .priority)
    }
}

public enum SchedulerEvent {
    public static let taskReserved = "TaskReserved"
    public static let taskStarted = "TaskStarted"
    public static let agentSpawnRequested = "AgentSpawnRequested"
    public static let taskFailed = "TaskFailed"
    public static let taskCompleted = "TaskCompleted"
}

public enum SchedulerError: Error, Equatable {
    case notARepository
}

public actor Scheduler {
    public typealias Provisioner = @Sendable (_ repo: URL, _ agentID: String, _ mode: WorktreeMode) async throws -> WorktreeInfo
    public typealias PlanningReader = @Sendable (_ worktree: URL) -> PlanningStatus

    private let bus: EventBus?
    private let provision: Provisioner
    private let planningStatus: PlanningReader
    private let now: @Sendable () -> Date

    public private(set) var tasks: [String: SchedulerTask] = [:]
    public private(set) var leases: Set<String> = []
    private var modes: [String: WorktreeMode] = [:]
    private var autoTick: Task<Void, Never>?

    public init(
        bus: EventBus? = nil,
        provision: @escaping Provisioner = { repo, agentID, mode in
            try await GitWorktrees().provision(repo: repo, agentId: agentID, mode: mode)
        },
        planningStatus: @escaping PlanningReader = { PlanningGate.status(of: $0) },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.bus = bus
        self.provision = provision
        self.planningStatus = planningStatus
        self.now = now
    }

    public static func taskID(projectID: String, text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "\(projectID)-gsd-\(String(hash, radix: 16))"
    }

    public func tasks(projectID: String) -> [SchedulerTask] {
        tasks.values.filter { $0.projectID == projectID }
    }

    public func worktreeMode(for projectID: String) -> WorktreeMode {
        modes[projectID] ?? .gitWorktree
    }

    public func setWorktreeMode(_ mode: WorktreeMode, for projectID: String) {
        modes[projectID] = mode
    }

    public func insert(_ task: SchedulerTask) {
        tasks[task.id] = task
        if let lease = task.leaseResource { leases.insert(lease) }
    }

    public func load(projectID: String, repo: URL) throws {
        guard let root = PlanningGate.repositoryRoot(containing: repo) else { throw SchedulerError.notARepository }
        let file = PlanningGate.planningFolder(of: root).appending(path: "task.md")
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return }

        var fresh: [SchedulerTask] = []
        var previous: String?
        for item in PlanningGate.roadmapItems(content) where !item.text.isEmpty {
            let id = Self.taskID(projectID: projectID, text: item.text)
            fresh.append(SchedulerTask(id: id, projectID: projectID, title: item.text,
                                       dependencies: previous.map { [$0] } ?? [],
                                       status: item.checked ? .completed : .pending))
            previous = id
        }
        let freshIDs = Set(fresh.map(\.id))
        tasks = tasks.filter { id, task in
            task.projectID != projectID || freshIDs.contains(id) || task.status.survivesReload
        }
        for var task in fresh {
            if let existing = tasks[task.id], existing.status.survivesReload {
                task.status = existing.status
                task.assignedAgentID = existing.assignedAgentID
                task.leaseResource = existing.leaseResource
                task.worktreePath = existing.worktreePath
            }
            tasks[task.id] = task
        }
    }

    public func trigger(projectID: String, repo: URL, mode: WorktreeMode? = nil) async throws {
        if let mode { modes[projectID] = mode }
        try? load(projectID: projectID, repo: repo)
        try await tick(projectID: projectID, repo: repo)
    }

    public func tick(projectID: String, repo: URL) async throws {
        try Task.checkCancellation()

        let toReady = tasks.values.filter { task in
            task.projectID == projectID && task.status == .pending
                && task.dependencies.allSatisfy { tasks[$0]?.status == .completed }
        }.map(\.id)
        for id in toReady {
            guard var task = tasks[id] else { continue }
            task.status = .ready
            tasks[id] = task
            await publish(SchedulerEvent.taskReserved, prefix: "sched", task: task)
        }

        var started: [(id: String, agentID: String, title: String)] = []
        for task in tasks.values where task.projectID == projectID && task.status == .ready {
            let lease = "worktree:\(task.id)"
            guard !leases.contains(lease) else { continue }
            leases.insert(lease)
            var running = task
            let agentID = "agent-\(task.id)"
            running.status = .running
            running.assignedAgentID = agentID
            running.leaseResource = lease
            tasks[task.id] = running
            await publish(SchedulerEvent.taskStarted, prefix: "sched", task: running,
                          data: ["agent_id": .string(agentID)])
            started.append((task.id, agentID, task.title))
        }
        if !started.isEmpty {
            let mode = worktreeMode(for: projectID)
            let provision = provision
            await withTaskGroup(of: (String, String, String, Result<WorktreeInfo, any Error>).self) { group in
                for entry in started {
                    group.addTask {
                        do {
                            return (entry.id, entry.agentID, entry.title,
                                    .success(try await provision(repo, entry.agentID, mode)))
                        } catch {
                            return (entry.id, entry.agentID, entry.title, .failure(error))
                        }
                    }
                }
                for await (id, agentID, title, result) in group {
                    await provisioned(taskID: id, projectID: projectID, agentID: agentID, title: title, result: result)
                }
            }
        }

        let reader = planningStatus
        for task in tasks.values where task.projectID == projectID && task.status == .running {
            guard let path = task.worktreePath else { continue }
            let status = reader(URL(fileURLWithPath: path, isDirectory: true))
            guard status.hasPlanning, status.reportedComplete else { continue }
            var done = task
            done.status = .completed
            if let lease = done.leaseResource { leases.remove(lease) }
            done.leaseResource = nil
            tasks[task.id] = done
            await publish(SchedulerEvent.taskCompleted, prefix: "sched", task: done)
        }
    }

    private func provisioned(taskID: String, projectID: String, agentID: String, title: String,
                             result: Result<WorktreeInfo, any Error>) async {
        guard var task = tasks[taskID] else { return }
        if case .success(let info) = result {
            task.worktreePath = info.path
            tasks[taskID] = task
            guard task.status == .running, task.assignedAgentID == agentID else { return }
            await publish(SchedulerEvent.agentSpawnRequested, prefix: "sched", task: task, data: [
                "agent_id": .string(agentID), "worktree_path": .string(info.path), "task_title": .string(title),
            ])
        } else {
            guard case .failure(let error) = result else {
                preconditionFailure("Invalid enum case")
            }
            guard task.status == .running, task.assignedAgentID == agentID else { return }
            task.status = .failed
            if let lease = task.leaseResource { leases.remove(lease) }
            task.leaseResource = nil
            task.assignedAgentID = nil
            tasks[taskID] = task
            await publish(SchedulerEvent.taskFailed, prefix: "sched", task: task,
                          data: ["error": .string(String(describing: error))])
        }
    }

    @discardableResult
    public func cancel(taskID: String) async -> Bool {
        guard var task = tasks[taskID], task.status == .running else { return false }
        task.status = .failed
        task.assignedAgentID = nil
        if let lease = task.leaseResource { leases.remove(lease) }
        task.leaseResource = nil
        tasks[taskID] = task
        await publish(SchedulerEvent.taskFailed, prefix: "cancel", task: task,
                      data: ["reason": .string("Cancelled by user")])
        return true
    }

    public func startAutoTick(on bus: EventBus) async {
        guard autoTick == nil else { return }
        let events = await bus.subscribe()
        autoTick = Task.detached { [weak self] in
            for await event in events {
                guard event.type == BusEventType.planningUpdated, let projectID = event.taskID,
                      case .object(let data) = event.data,
                      case .string(let planningDir)? = data["planning_dir"] else { continue }
                let repo = URL(fileURLWithPath: planningDir, isDirectory: true).deletingLastPathComponent()
                guard !repo.path.isEmpty, let self else { continue }
                try? await self.trigger(projectID: projectID, repo: repo)
            }
        }
    }

    public func stopAutoTick() {
        autoTick?.cancel()
        autoTick = nil
    }

    public var isAutoTicking: Bool { autoTick != nil }

    private func publish(_ type: String, prefix: String, task: SchedulerTask, data: [String: JSONValue] = [:]) async {
        guard let bus else { return }
        await bus.publish(BusEvent(type: type, correlationID: BusEvent.correlationID(prefix: prefix),
                                   taskID: task.projectID, agentID: task.id, data: .object(data), date: now()))
    }
}
