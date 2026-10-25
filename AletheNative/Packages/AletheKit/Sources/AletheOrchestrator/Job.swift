import Foundation
import AletheIntegrations

public struct Job: Hashable, Sendable, Identifiable {
    public var id: String
    public var plannerID: String?
    public var agent: String
    public var runID: String
    public var runLabel: String?
    public var rulesName: String?
    public var model: String?
    public var effort: String?
    public var spec: String
    public var cwd: String
    public var status: JobStatus
    public var threadID: String?
    public var activeTurnID: String?
    public var reply: String = ""
    public var report: String = ""
    public var plan: [String] = []
    public var diff: String?
    public var tokens: OrderedJSON?
    public var costUSD: Double?
    public var quota: OrderedJSON?
    public var outcome: String?
    public var startedAt: UInt64?
    public var endedAt: UInt64?
    public var worktree: String?
    public var timeoutMs: UInt64?
    public var approvalPolicy: String
    public var sandbox: String
    public var webSearch: Bool
    public var pending: OrderedJSON?
    public var inbox: [String] = []
    public var routing: OrderedJSON?
    public var awaitingSteer = false
    public var nextRequestID = OrchestratorLimits.firstRequestID

    public static let defaultApprovalPolicy = "never"
    public static let defaultSandbox = "workspace-write"

    public init(
        id: String,
        plannerID: String?,
        agent: String,
        runID: String,
        runLabel: String?,
        spec: String,
        cwd: String,
        status: JobStatus = .queued,
        worktree: String? = nil,
        timeoutMs: UInt64? = OrchestratorLimits.defaultJobTimeoutMs,
        approvalPolicy: String = Job.defaultApprovalPolicy,
        sandbox: String = Job.defaultSandbox,
        webSearch: Bool = false
    ) {
        self.id = id
        self.plannerID = plannerID
        self.agent = agent
        self.runID = runID
        self.runLabel = runLabel
        self.spec = spec
        self.cwd = cwd
        self.status = status
        self.worktree = worktree
        self.timeoutMs = timeoutMs
        self.approvalPolicy = approvalPolicy
        self.sandbox = sandbox
        self.webSearch = webSearch
    }

    public var settled: Bool { status.settled }

    public var approvalPolicyValue: OrderedJSON {
        (try? OrderedJSON.parse(approvalPolicy)) ?? .string(Job.defaultApprovalPolicy)
    }

    public func elapsedSeconds(nowMs: UInt64) -> Double? {
        guard let startedAt else { return nil }
        let end = endedAt ?? nowMs
        return Double(end >= startedAt ? end - startedAt : 0) / 1000
    }

    public func snapshot(nowMs: UInt64) -> JobSnapshot {
        JobSnapshot(
            id: id,
            plannerID: plannerID,
            agent: agent,
            runID: runID,
            runLabel: runLabel,
            spec: spec,
            cwd: cwd,
            status: status,
            threadID: threadID,
            outcome: outcome,
            seconds: elapsedSeconds(nowMs: nowMs),
            plan: plan,
            tokens: tokens,
            costUSD: costUSD,
            quota: quota,
            routing: routing,
            worktree: worktree,
            pendingApproval: pending,
            hasDiff: diff != nil,
            summary: orchestratorTail(report.isEmpty ? reply : report, limit: OrchestratorLimits.summaryLimit)
        )
    }

    public var record: OrderedJSON {
        var object: OrderedJSONObject = [
            "id": .string(id),
            "plannerId": .optional(plannerID),
            "agent": .string(agent),
            "runId": .string(runID),
            "runLabel": .optional(runLabel),
            "spec": .string(spec),
            "cwd": .string(cwd),
            "status": .string(status.rawValue),
            "threadId": .optional(threadID),
            "outcome": .optional(outcome),
            "plan": .array(plan.map(OrderedJSON.string)),
            "tokens": .optional(tokens),
            "costUsd": .optional(costUSD),
            "worktree": .optional(worktree),
            "approvalPolicy": .string(approvalPolicy),
            "sandbox": .string(sandbox),
            "webSearch": .bool(webSearch),
            "summary": .string(report),
            "startedAt": .optional(startedAt),
            "endedAt": .optional(endedAt),
        ]
        if let rulesName { object["rules"] = .string(rulesName) }
        if let model { object["model"] = .string(model) }
        if let effort { object["effort"] = .string(effort) }
        return .object(object)
    }

    public init?(record: OrderedJSON) {
        guard let object = record.objectValue, let id = object["id"]?.stringValue else { return nil }
        func text(_ key: String) -> String? { object[key]?.stringValue }
        var status = text("status").flatMap(JobStatus.init(rawValue:)) ?? .done
        if status == .running || status == .queued { status = .interrupted }
        self.init(
            id: id,
            plannerID: text("plannerId"),
            agent: text("agent") ?? WorkerAgent.codex,
            runID: text("runId") ?? "run-00",
            runLabel: text("runLabel"),
            spec: text("spec") ?? "",
            cwd: text("cwd") ?? "",
            status: status,
            worktree: text("worktree"),
            timeoutMs: OrchestratorLimits.defaultJobTimeoutMs,
            approvalPolicy: text("approvalPolicy") ?? Job.defaultApprovalPolicy,
            sandbox: text("sandbox") ?? Job.defaultSandbox,
            webSearch: object["webSearch"]?.boolValue ?? false
        )
        rulesName = text("rules")
        model = text("model")
        effort = text("effort")
        threadID = text("threadId")
        report = text("summary") ?? ""
        plan = object["plan"]?.arrayValue?.compactMap(\.stringValue) ?? []
        tokens = object["tokens"]?.nonNull
        costUSD = object["costUsd"]?.doubleValue
        outcome = text("outcome")
        startedAt = object["startedAt"]?.uint64Value
        endedAt = object["endedAt"]?.uint64Value
    }
}

public struct JobSnapshot: Hashable, Sendable, Identifiable {
    public var id: String
    public var plannerID: String?
    public var agent: String
    public var runID: String
    public var runLabel: String?
    public var spec: String
    public var cwd: String
    public var status: JobStatus
    public var threadID: String?
    public var outcome: String?
    public var seconds: Double?
    public var plan: [String]
    public var tokens: OrderedJSON?
    public var costUSD: Double?
    public var quota: OrderedJSON?
    public var routing: OrderedJSON?
    public var worktree: String?
    public var pendingApproval: OrderedJSON?
    public var hasDiff: Bool
    public var summary: String
    public var native: Bool

    public init(
        id: String,
        plannerID: String?,
        agent: String,
        runID: String,
        runLabel: String?,
        spec: String,
        cwd: String,
        status: JobStatus,
        threadID: String? = nil,
        outcome: String? = nil,
        seconds: Double? = nil,
        plan: [String] = [],
        tokens: OrderedJSON? = nil,
        costUSD: Double? = nil,
        quota: OrderedJSON? = nil,
        routing: OrderedJSON? = nil,
        worktree: String? = nil,
        pendingApproval: OrderedJSON? = nil,
        hasDiff: Bool = false,
        summary: String = "",
        native: Bool = false
    ) {
        self.id = id
        self.plannerID = plannerID
        self.agent = agent
        self.runID = runID
        self.runLabel = runLabel
        self.spec = spec
        self.cwd = cwd
        self.status = status
        self.threadID = threadID
        self.outcome = outcome
        self.seconds = seconds
        self.plan = plan
        self.tokens = tokens
        self.costUSD = costUSD
        self.quota = quota
        self.routing = routing
        self.worktree = worktree
        self.pendingApproval = pendingApproval
        self.hasDiff = hasDiff
        self.summary = summary
        self.native = native
    }

    public var json: OrderedJSON {
        var object: OrderedJSONObject = [
            "id": .string(id),
            "plannerId": .optional(plannerID),
            "agent": .string(agent),
            "runId": .string(runID),
            "runLabel": .optional(runLabel),
            "spec": .string(spec),
            "cwd": .string(cwd),
            "status": .string(status.rawValue),
            "threadId": .optional(threadID),
            "outcome": .optional(outcome),
            "seconds": .optional(seconds),
            "plan": .array(plan.map(OrderedJSON.string)),
            "tokens": .optional(tokens),
            "costUsd": .optional(costUSD),
            "quota": .optional(quota),
            "routing": .optional(routing),
            "worktree": .optional(worktree),
            "pendingApproval": .optional(pendingApproval),
            "hasDiff": .bool(hasDiff),
            "summary": .string(summary),
        ]
        if native { object["native"] = .bool(true) }
        return .object(object)
    }
}

public struct OrchestratorSnapshot: Hashable, Sendable {
    public var jobs: [JobSnapshot]
    public var planners: [Planner]
    public var running: Int
    public var queued: Int
    public var concurrencyLimit: Int

    public init(
        jobs: [JobSnapshot] = [],
        planners: [Planner] = [],
        running: Int = 0,
        queued: Int = 0,
        concurrencyLimit: Int = OrchestratorLimits.defaultConcurrency
    ) {
        self.jobs = jobs
        self.planners = planners
        self.running = running
        self.queued = queued
        self.concurrencyLimit = concurrencyLimit
    }

    public var json: OrderedJSON {
        [
            "jobs": .array(jobs.map(\.json)),
            "planners": .array(planners.map(\.json)),
            "running": .integer(running),
            "queued": .integer(queued),
            "concurrencyLimit": .integer(concurrencyLimit),
        ]
    }
}
