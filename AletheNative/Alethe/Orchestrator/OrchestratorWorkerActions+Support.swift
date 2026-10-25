import AletheDesign
import AletheDocuments
import AletheFoundation
import AletheIntegrations
import AletheModel
import AletheOrchestrator
import SwiftUI

enum WorkerActions {
    static func canMessage(_ job: JobSnapshot) -> Bool {
        if job.native { return false }
        if case .cancelled = job.status {
            return false
        } else if case .interrupted = job.status {
            return job.threadID != nil
        } else if case .released = job.status {
            return job.threadID != nil
        } else {
            return true
        }
    }

    static func canCancel(_ job: JobSnapshot) -> Bool {
        !job.native && !job.status.settled
    }

    static func cancelAsks(_ job: JobSnapshot) -> Bool {
        job.status == .running || job.status == .blocked
    }

    static func canRelease(_ job: JobSnapshot) -> Bool {
        guard !job.native else { return false }
        if case .done = job.status {
            return true
        } else if case .failed = job.status {
            return true
        } else if case .interrupted = job.status {
            return true
        } else {
            return false
        }
    }

    static func elsewhere(ask: WorkerAsk, job: JobSnapshot) -> String? {
        guard let cwd = ask.cwd, !cwd.isEmpty else { return nil }
        let own = standardized(job.cwd)
        let asked = standardized(cwd)
        if asked == own || asked.hasPrefix(own.hasSuffix("/") ? own : own + "/") { return nil }
        return cwd
    }

    private static func standardized(_ path: String) -> String {
        URL(filePath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func diffText(_ line: DiffLine) -> String {
        if case .added = line.kind {
            return "+" + line.text
        } else if case .removed = line.kind {
            return "-" + line.text
        } else if case .context = line.kind {
            return " " + line.text
        } else {
            return line.text
        }
    }
}

enum WorkerMessageMode: String {
    case steer, resume, next

    init(_ job: JobSnapshot) {
        if case .running = job.status {
            self = .steer
        } else if case .interrupted = job.status {
            self = .resume
        } else if case .released = job.status {
            self = .resume
        } else {
            self = .next
        }
    }

    private static let placeholderValues: [WorkerMessageMode: String] = [
        .steer: "orchestrator.steerPlaceholder",
        .resume: "orchestrator.resumePlaceholder",
    ]

    var placeholder: LocalizedStringKey {
        LocalizedStringKey(Self.placeholderValues[self] ?? "orchestrator.sendPlaceholder")
    }

    private static let labelValues: [WorkerMessageMode: String] = [
        .steer: "orchestrator.modeSteer",
        .resume: "orchestrator.modeResume",
    ]

    var label: LocalizedStringKey {
        LocalizedStringKey(Self.labelValues[self] ?? "orchestrator.modeNext")
    }

    private static let hintValues: [WorkerMessageMode: String] = [
        .steer: "orchestrator.steerHint",
        .resume: "orchestrator.resumeHint",
    ]

    var hint: LocalizedStringKey {
        LocalizedStringKey(Self.hintValues[self] ?? "orchestrator.sendHint")
    }
}

struct WorkerAsk: Equatable {
    var kind: CodexApprovalRequest.Kind
    var command: String?
    var cwd: String?
    var reason: String?

    init?(_ job: JobSnapshot) {
        guard let object = job.pendingApproval?.objectValue else { return nil }
        kind = object["kind"]?.stringValue.flatMap(CodexApprovalRequest.Kind.init(rawValue:)) ?? .command
        command = object["command"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        cwd = object["cwd"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        reason = object["reason"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    }
}

struct WorkerDecision: Identifiable {
    let decision: CodexApprovalDecision
    let label: LocalizedStringKey
    let hint: LocalizedStringKey
    var id: String { decision.rawValue }

    static var all: [WorkerDecision] {
        [
            WorkerDecision(decision: .accept, label: "orchestrator.answerAccept", hint: "orchestrator.answerAcceptTitle"),
            WorkerDecision(decision: .acceptForSession, label: "orchestrator.answerSession", hint: "orchestrator.answerSessionTitle"),
            WorkerDecision(decision: .decline, label: "orchestrator.answerDecline", hint: "orchestrator.answerDeclineTitle"),
            WorkerDecision(decision: .abort, label: "orchestrator.answerAbort", hint: "orchestrator.answerAbortTitle"),
        ]
    }
}

enum WorkerDiffState: Equatable {
    case idle, loading
    case loaded(DiffDocument)
}

struct WorkerActionFailure: Equatable {
    var title: String
    var detail: String

    init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    init(title: String, error: any Error) {
        self.title = title
        detail = (error as? OrchestratorToolError)?.message ?? error.localizedDescription
    }

    var logLine: String { "\(title): \(detail)" }
}

extension OrchestratorService {
    func cancel(job: String) async throws -> OrderedJSON {
        try await boardTool("alethe_cancel", ["jobIds": .array([.string(job)])])
    }

    func release(job: String) async throws -> OrderedJSON {
        try await boardTool("alethe_release", ["jobIds": .array([.string(job)])])
    }

    private func boardTool(_ name: String, _ arguments: OrderedJSONObject) async throws -> OrderedJSON {
        guard let core = await prepared() else { throw OrchestratorToolError("the orchestrator is not running") }
        return try await core.callTool(name: name, arguments: arguments, planner: nil)
    }
}
