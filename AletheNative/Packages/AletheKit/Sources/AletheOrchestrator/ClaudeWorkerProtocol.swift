import AletheGit
import AletheIntegrations
import Foundation

public enum ClaudeWorkerEvent: Hashable, Sendable {
    case ignored
    case updated
    case turnEnded(ClaudeTurnEnd)
}

public struct ClaudeTurnEnd: Hashable, Sendable {
    public var status: JobStatus
    public var outcome: String?
    public var text: String
    public var announce: Bool

    public init(status: JobStatus, outcome: String?, text: String, announce: Bool) {
        self.status = status
        self.outcome = outcome
        self.text = text
        self.announce = announce
    }
}

public enum ClaudeSteer: Hashable, Sendable {
    case interrupt(jobID: String, request: OrderedJSON)
    case queued(jobID: String, waiting: Int)

    public var result: OrderedJSON {
        if case .interrupt(let jobID, _) = self {
            return ["steered": .string(jobID)]
        } else {
            guard case .queued(let jobID, let waiting) = self else {
                preconditionFailure("Invalid enum case")
            }
            return [
                "queued": .string(jobID),
                "waiting": .integer(waiting),
                "note": "worker is not running a turn; the steer starts as its next one",
            ]
        }
    }
}

public enum ClaudeWorkerProtocol {
    public static func arguments(_ launcher: Launcher, resuming sessionID: String?) -> [String] {
        guard let sessionID, !sessionID.isEmpty else { return launcher.arguments }
        return launcher.arguments + ["--resume", sessionID]
    }

    public static func userTurn(_ text: String) -> OrderedJSON {
        [
            "type": "user",
            "message": [
                "role": "user",
                "content": [["type": "text", "text": .string(text)]],
            ],
        ]
    }

    public static func interrupt(requestID: String, cancelQueued: Bool = false) -> OrderedJSON {
        var request: OrderedJSONObject = ["subtype": "interrupt"]
        if cancelQueued { request["cancel_queued"] = .bool(true) }
        return [
            "type": "control_request",
            "request_id": .string(requestID),
            "request": .object(request),
        ]
    }

    public static func line(_ message: OrderedJSON) -> Data {
        Data((message.compactRendered() + "\n").utf8)
    }

    public static func parse(line: String) -> OrderedJSON? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? OrderedJSON.parse(trimmed)
    }

    public static func firstTurn(_ job: inout Job) -> OrderedJSON {
        userTurn(job.inbox.isEmpty ? job.spec : job.inbox.removeFirst())
    }

    public static func nextTurn(_ job: inout Job) -> OrderedJSON? {
        guard job.threadID != nil, !job.inbox.isEmpty else { return nil }
        return userTurn(job.inbox.removeFirst())
    }

    public static func handle(_ message: OrderedJSON, job: inout Job) -> ClaudeWorkerEvent {
        guard let object = message.objectValue else { return .ignored }
        let eventType = object["type"]?.stringValue ?? ""
        if case "rate_limit_event" = eventType {
            guard let info = object["rate_limit_info"] else { return .ignored }
            job.quota = info
            return .updated
        } else if case "system" = eventType {
            let subtype = object["subtype"]?.stringValue ?? ""
            if case "init" = subtype {
                guard let sessionID = object["session_id"]?.stringValue else { return .ignored }
                if job.threadID == nil { job.threadID = sessionID }
                return .updated
            } else if case "permission_denied" = subtype {
                let note = object["message"]?.stringValue ?? "a tool call was denied permission"
                appendReply("\n[blocked] \(note)\n", to: &job)
                return .updated
            } else {
                return .ignored
            }
        } else if case "assistant" = eventType {
            let blocks = object["message"]?.objectValue?["content"]?.arrayValue ?? []
            let text = blocks
                .filter { $0.objectValue?["type"]?.stringValue == "text" }
                .compactMap { $0.objectValue?["text"]?.stringValue }
                .joined()
            guard !text.isEmpty else { return .ignored }
            appendReply(text, to: &job)
            return .updated
        } else if case "result" = eventType {
            return .turnEnded(result(object, job: &job))
        } else {
            return .ignored
        }
    }

    private static func result(_ object: OrderedJSONObject, job: inout Job) -> ClaudeTurnEnd {
        let isError = object["is_error"]?.boolValue ?? false
        let resultText = (object["result"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let usage = object["usage"] {
            let last = TokenCounts.claude(usage: usage)
            let current: OrderedJSON? = job.tokens?.objectValue?["total"]
            let total = current.map { TokenCounts.adding($0, last) } ?? last
            job.tokens = ["total": total, "last": last]
        }
        if let cost = object["total_cost_usd"]?.doubleValue, cost.isFinite, cost >= 0 {
            job.costUSD = (job.costUSD ?? 0) + cost
        }
        let summary = resultText.isEmpty
            ? orchestratorTail(job.reply, limit: OrchestratorLimits.replyLimit)
            : resultText
        if job.awaitingSteer {
            job.awaitingSteer = false
            return ClaudeTurnEnd(status: .interrupted, outcome: nil, text: "", announce: false)
        }
        return ClaudeTurnEnd(
            status: isError ? .failed : .done,
            outcome: isError ? "failed" : "succeeded",
            text: summary,
            announce: true
        )
    }

    public static func steer(_ job: inout Job, message: String, workerIsLive: Bool) -> ClaudeSteer {
        guard job.status == .running, workerIsLive else {
            job.inbox.append(message)
            return .queued(jobID: job.id, waiting: job.inbox.count)
        }
        job.inbox.insert(message, at: 0)
        job.awaitingSteer = true
        return .interrupt(jobID: job.id, request: interrupt(requestID: nextInterruptID(&job)))
    }

    public static func cancel(_ job: inout Job) -> OrderedJSON {
        job.awaitingSteer = false
        return interrupt(requestID: nextInterruptID(&job), cancelQueued: true)
    }

    public static func uncommittedDiff(in cwd: String, runner: GitRunner = GitRunner()) async -> String? {
        let folder = URL(fileURLWithPath: cwd, isDirectory: true)
        guard let output = try? await runner.run(["diff", "--no-color", "--no-ext-diff", "HEAD"], in: folder) else {
            return nil
        }
        let diff = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return diff.isEmpty ? nil : diff
    }

    private static func nextInterruptID(_ job: inout Job) -> String {
        job.nextRequestID += 1
        return "\(job.id)-interrupt-\(job.nextRequestID)"
    }

    private static func appendReply(_ text: String, to job: inout Job) {
        job.reply += text
        let scalars = job.reply.unicodeScalars
        guard scalars.count > OrchestratorLimits.replyLimit else { return }
        var kept = String.UnicodeScalarView()
        kept.append(contentsOf: scalars.suffix(OrchestratorLimits.replyLimit))
        job.reply = String(kept)
    }
}
