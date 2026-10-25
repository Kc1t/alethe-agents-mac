import Foundation
import AletheIntegrations

public enum CodexWorkerEvent: Hashable, Sendable {
    case threadReady(threadID: String)
    case turnStarted(turnID: String?)
    case replyDelta(String)
    case report(String)
    case planUpdated([String])
    case diffUpdated(String?)
    case tokensUpdated(OrderedJSON?)
    case approvalRequested(CodexApprovalRequest)
    case turnEnded(succeeded: Bool, summary: String)
    case requestFailed(id: OrderedJSON, message: String)
}

public struct CodexApprovalRequest: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case command
        case fileChange
    }

    public var rpcID: OrderedJSON
    public var kind: Kind
    public var command: String?
    public var cwd: String?
    public var reason: String?
    public var askedAtMs: UInt64

    public init(rpcID: OrderedJSON, kind: Kind, command: String?, cwd: String?, reason: String?, askedAtMs: UInt64) {
        self.rpcID = rpcID
        self.kind = kind
        self.command = command
        self.cwd = cwd
        self.reason = reason
        self.askedAtMs = askedAtMs
    }

    public var json: OrderedJSON {
        [
            "rpcId": rpcID,
            "kind": .string(kind.rawValue),
            "command": .optional(command),
            "cwd": .optional(cwd),
            "reason": .optional(reason),
            "askedAtMs": .unsigned(askedAtMs),
        ]
    }
}

public enum CodexApprovalDecision: String, Hashable, Sendable, CaseIterable {
    case accept
    case acceptForSession
    case decline
    case abort
}

public enum CodexApprovalPolicy {
    public static func policy(askForApproval: Bool) -> (approvalPolicy: String, sandbox: String) {
        guard askForApproval else {
            return (OrderedJSON.string(Job.defaultApprovalPolicy).compactRendered(), Job.defaultSandbox)
        }
        let granular: OrderedJSON = [
            "granular": [
                "sandbox_approval": true,
                "request_permissions": true,
                "rules": true,
                "skill_approval": true,
                "mcp_elicitations": true,
            ],
        ]
        return (granular.compactRendered(), Job.defaultSandbox)
    }
}

public struct CodexWorkerStep: Hashable, Sendable {
    public var outgoing: [OrderedJSON]
    public var events: [CodexWorkerEvent]

    public init(outgoing: [OrderedJSON] = [], events: [CodexWorkerEvent] = []) {
        self.outgoing = outgoing
        self.events = events
    }
}

public struct CodexWorkerSession: Hashable, Sendable {
    public static let initializeID: OrderedJSON = 1
    public static let openThreadID: OrderedJSON = 2
    public static let firstTurnID: OrderedJSON = 3

    public let jobID: String
    public let cwd: String
    public let firstTurn: String
    public let resumeThreadID: String?
    public let approvalPolicy: OrderedJSON
    public let sandbox: String
    public let webSearch: Bool
    public var model: String?
    public var effort: String?
    public var disabledPlugins: [String] = []

    public private(set) var threadID: String?
    public private(set) var activeTurnID: String?
    public private(set) var pending: CodexApprovalRequest?
    public private(set) var nextRequestID: Int
    public private(set) var reply = ""
    public private(set) var report = ""

    public init(
        jobID: String,
        cwd: String,
        firstTurn: String,
        resumeThreadID: String? = nil,
        approvalPolicy: OrderedJSON = .string(Job.defaultApprovalPolicy),
        sandbox: String = Job.defaultSandbox,
        webSearch: Bool = false,
        nextRequestID: Int = OrchestratorLimits.firstRequestID
    ) {
        self.jobID = jobID
        self.cwd = cwd
        self.firstTurn = firstTurn
        self.resumeThreadID = resumeThreadID
        self.approvalPolicy = approvalPolicy
        self.sandbox = sandbox
        self.webSearch = webSearch
        self.nextRequestID = nextRequestID
    }

    public init(job: Job, firstTurn: String, disabledPlugins: [String] = []) {
        self.init(
            jobID: job.id,
            cwd: job.cwd,
            firstTurn: firstTurn,
            resumeThreadID: job.threadID,
            approvalPolicy: job.approvalPolicyValue,
            sandbox: job.sandbox,
            webSearch: job.webSearch,
            nextRequestID: job.nextRequestID
        )
        model = job.model; effort = job.effort; self.disabledPlugins = disabledPlugins
    }

    public func handshake() -> [OrderedJSON] {
        let initialize: OrderedJSON = [
            "id": Self.initializeID,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "alethe-orchestrator", "title": "Alethe", "version": "1"],
                "capabilities": ["experimentalApi": true],
            ],
        ]
        var opening: OrderedJSON
        if let resumeThreadID {
            opening = [
                "id": Self.openThreadID,
                "method": "thread/resume",
                "params": ["threadId": .string(resumeThreadID), "cwd": .string(cwd)],
            ]
        } else {
            opening = [
                "id": Self.openThreadID,
                "method": "thread/start",
                "params": [
                    "cwd": .string(cwd),
                    "approvalPolicy": approvalPolicy,
                    "approvalsReviewer": "user",
                    "sandbox": .string(sandbox),
                    "config": ["tools": ["web_search": ["mode": webSearch ? "live" : "disabled"]]],
                ],
            ]
        }
        if model != nil || effort != nil || !disabledPlugins.isEmpty || sandbox == "read-only",
           var object = opening.objectValue, var params = object["params"]?.objectValue {
            if let model { params["model"] = .string(model) }
            params["approvalPolicy"] = approvalPolicy
            params["sandbox"] = .string(sandbox)
            var config = params["config"]?.objectValue ?? [:]
            if let effort { config["model_reasoning_effort"] = .string(effort) }
            if !disabledPlugins.isEmpty {
                var plugins: OrderedJSONObject = [:]
                for plugin in disabledPlugins { plugins[plugin] = ["enabled": false] }
                config["plugins"] = .object(plugins)
            }
            if !config.isEmpty { params["config"] = .object(config) }
            object["params"] = .object(params); opening = .object(object)
        }
        return [initialize, ["method": "initialized"], opening]
    }

    public mutating func startTurn(_ text: String) throws(OrchestratorToolError) -> OrderedJSON {
        guard let threadID else { throw OrchestratorToolError("job \(jobID) has no thread") }
        reply = ""
        report = ""
        return request("turn/start", [
            "threadId": .string(threadID),
            "input": [["type": "text", "text": .string(text)]],
            "approvalPolicy": "never",
        ])
    }

    public mutating func steer(_ text: String) throws(OrchestratorToolError) -> OrderedJSON {
        guard let threadID else { throw OrchestratorToolError("job \(jobID) has no thread yet") }
        guard let activeTurnID else { throw OrchestratorToolError("job \(jobID) has no running turn to steer") }
        return request("turn/steer", [
            "threadId": .string(threadID),
            "input": [["type": "text", "text": .string(text)]],
            "expectedTurnId": .string(activeTurnID),
        ])
    }

    public mutating func interrupt() -> OrderedJSON? {
        guard let threadID, let activeTurnID else { return nil }
        return request("turn/interrupt", ["threadId": .string(threadID), "turnId": .string(activeTurnID)])
    }

    public mutating func answer(_ decision: String) throws(OrchestratorToolError) -> OrderedJSON {
        guard let decision = CodexApprovalDecision(rawValue: decision) else {
            let names = CodexApprovalDecision.allCases.map(\.rawValue).joined(separator: ", ")
            throw OrchestratorToolError("decision must be one of \(names)")
        }
        return try answer(decision)
    }

    public mutating func answer(_ decision: CodexApprovalDecision) throws(OrchestratorToolError) -> OrderedJSON {
        guard let pending else { throw OrchestratorToolError("job \(jobID) is not waiting on anything") }
        self.pending = nil
        return ["id": pending.rpcID, "result": ["decision": .string(decision.rawValue)]]
    }

    private mutating func request(_ method: String, _ params: OrderedJSON) -> OrderedJSON {
        nextRequestID += 1
        return ["id": .integer(nextRequestID), "method": .string(method), "params": params]
    }

    public mutating func receive(line: String, nowMs: UInt64 = CodexWorkerSession.currentMilliseconds()) -> CodexWorkerStep {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let message = try? OrderedJSON.parse(trimmed) else { return CodexWorkerStep() }
        return receive(message, nowMs: nowMs)
    }

    public mutating func receive(_ message: OrderedJSON, nowMs: UInt64 = CodexWorkerSession.currentMilliseconds()) -> CodexWorkerStep {
        guard let object = message.objectValue else { return CodexWorkerStep() }
        let method = object["method"]?.stringValue ?? ""
        let params = object["params"]?.objectValue ?? [:]

        if let rpcID = object["id"], !method.isEmpty {
            return request(rpcID: rpcID, method: method, params: params, nowMs: nowMs)
        }
        if let id = object["id"] {
            return response(id: id, object: object)
        }

        switch method {
        case "turn/started":
            activeTurnID = params["turn"]?.objectValue?["id"]?.stringValue
            return CodexWorkerStep(events: [.turnStarted(turnID: activeTurnID)])
        case "item/completed":
            let item = params["item"]?.objectValue
            guard item?["type"]?.stringValue == "agentMessage" else { return CodexWorkerStep() }
            let text = (item?["text"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return CodexWorkerStep() }
            report = text
            return CodexWorkerStep(events: [.report(text)])
        case "item/agentMessage/delta":
            guard let delta = params["delta"]?.stringValue else { return CodexWorkerStep() }
            reply = Self.appendingReply(reply, delta)
            return CodexWorkerStep(events: [.replyDelta(delta)])
        case "turn/plan/updated":
            let steps = params["plan"]?.arrayValue?.compactMap { $0.objectValue?["step"]?.stringValue } ?? []
            return CodexWorkerStep(events: [.planUpdated(steps)])
        case "turn/diff/updated":
            return CodexWorkerStep(events: [.diffUpdated(params["diff"]?.stringValue)])
        case "thread/tokenUsage/updated":
            return CodexWorkerStep(events: [.tokensUpdated(params["tokenUsage"])])
        case "turn/completed", "turn/failed":
            let summary = report.isEmpty
                ? orchestratorTail(reply, limit: OrchestratorLimits.replyLimit)
                : report
            activeTurnID = nil
            pending = nil
            return CodexWorkerStep(events: [.turnEnded(succeeded: method == "turn/completed", summary: summary)])
        default:
            return CodexWorkerStep()
        }
    }

    private mutating func request(rpcID: OrderedJSON, method: String, params: OrderedJSONObject, nowMs: UInt64) -> CodexWorkerStep {
        let kind: CodexApprovalRequest.Kind
        switch method {
        case "item/commandExecution/requestApproval": kind = .command
        case "item/fileChange/requestApproval": kind = .fileChange
        default:
            return CodexWorkerStep(outgoing: [[
                "id": rpcID,
                "error": ["code": -32601, "message": .string("unsupported request \(method)")],
            ]])
        }
        let ask = CodexApprovalRequest(
            rpcID: rpcID,
            kind: kind,
            command: params["command"]?.stringValue,
            cwd: params["cwd"]?.stringValue,
            reason: params["reason"]?.stringValue,
            askedAtMs: nowMs
        )
        pending = ask
        return CodexWorkerStep(events: [.approvalRequested(ask)])
    }

    private mutating func response(id: OrderedJSON, object: OrderedJSONObject) -> CodexWorkerStep {
        if let error = object["error"] {
            let message = error.objectValue?["message"]?.stringValue ?? error.compactRendered()
            return CodexWorkerStep(events: [.requestFailed(id: id, message: message)])
        }
        guard id.intValue == Self.openThreadID.intValue,
              let threadID = object["result"]?.objectValue?["thread"]?.objectValue?["id"]?.stringValue
        else { return CodexWorkerStep() }
        self.threadID = threadID
        let turn: OrderedJSON = [
            "id": Self.firstTurnID,
            "method": "turn/start",
            "params": [
                "threadId": .string(threadID),
                "input": [["type": "text", "text": .string(firstTurn)]],
                "approvalPolicy": "never",
            ],
        ]
        return CodexWorkerStep(outgoing: [turn], events: [.threadReady(threadID: threadID)])
    }

    static func appendingReply(_ reply: String, _ delta: String) -> String {
        let joined = reply + delta
        let scalars = joined.unicodeScalars
        guard scalars.count > OrchestratorLimits.replyLimit else { return joined }
        var kept = String.UnicodeScalarView()
        kept.append(contentsOf: scalars.suffix(OrchestratorLimits.replyLimit))
        return String(kept)
    }

    public static func currentMilliseconds() -> UInt64 {
        UInt64(max(0, Date().timeIntervalSince1970 * 1000))
    }
}

extension Job {
    public mutating func apply(_ event: CodexWorkerEvent) {
        switch event {
        case .threadReady(let threadID): self.threadID = threadID
        case .turnStarted(let turnID): activeTurnID = turnID
        case .replyDelta(let delta): reply = CodexWorkerSession.appendingReply(reply, delta)
        case .report(let text): report = text
        case .planUpdated(let steps): plan = steps
        case .diffUpdated(let diff): self.diff = diff
        case .tokensUpdated(let tokens): self.tokens = tokens
        case .approvalRequested(let ask):
            pending = ask.json
            status = .blocked
        case .turnEnded: activeTurnID = nil
        case .requestFailed: break
        }
    }
}

extension CodexWorkerSession {
    public static func pump<Lines: AsyncSequence>(
        lines: Lines,
        handle: (String) async -> [OrderedJSON],
        write: (String) async throws -> Void
    ) async throws where Lines.Element == String {
        for try await line in lines {
            for message in await handle(line) {
                try await write(message.compactRendered())
            }
        }
    }
}
