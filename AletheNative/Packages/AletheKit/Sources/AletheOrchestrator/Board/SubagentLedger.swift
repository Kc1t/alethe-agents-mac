import Foundation
import AletheAgents

public struct SubagentLedger: Sendable {
    public struct Outcome: Equatable, Sendable {
        public var changed: Bool
        public var transcript: Transcript?

        public static let none = Outcome(changed: false)

        public init(changed: Bool, transcript: Transcript? = nil) {
            self.changed = changed
            self.transcript = transcript
        }
    }

    public struct Transcript: Equatable, Sendable {
        public var nodeID: String
        public var path: String

        public init(nodeID: String, path: String) {
            self.nodeID = nodeID
            self.path = path
        }
    }

    private struct PendingPrompt: Sendable {
        var description: String?
        var prompt: String?
    }

    static let pendingLimit = 32
    static let spawnerTools: Set<String> = ["Agent", "Task"]

    public private(set) var nodes: [NativeSubagent] = []
    public private(set) var transcripts: [String: String] = [:]
    private var pending: [PendingKey: [PendingPrompt]] = [:]
    private var incarnations: [String: String] = [:]

    private struct PendingKey: Hashable, Sendable {
        var planner: String?
        var agentType: String
    }

    public init() {}

    public mutating func ingest(_ hook: SubagentHook, planner: String?, sourceAgent: String, nowMs: UInt64) -> Outcome {
        if case "SubagentStart" = hook.event {
            return start(hook, planner: planner, sourceAgent: sourceAgent, nowMs: nowMs)
        } else if case "SubagentStop" = hook.event {
            return stop(hook, nowMs: nowMs)
        } else if case "PostToolUse" = hook.event, hook.agentID == nil {
            return postToolUse(hook, planner: planner, sourceAgent: sourceAgent, nowMs: nowMs)
        } else if case "PreToolUse" = hook.event {
            return preToolUse(hook, planner: planner, sourceAgent: sourceAgent, nowMs: nowMs)
        } else if case "TeammateIdle" = hook.event {
            return teammateIdle(hook, planner: planner)
        } else {
            return .none
        }
    }

    private func index(of id: String) -> Int? { nodes.firstIndex { $0.id == id } }

    private mutating func start(_ hook: SubagentHook, planner: String?, sourceAgent: String, nowMs: UInt64) -> Outcome {
        guard let id = hook.agentID, index(of: id) == nil else { return .none }
        let agentType = hook.agentType ?? "unknown"
        if let teammate = nodes.firstIndex(where: { $0.kind == .teammate && $0.plannerID == planner && $0.agentType == agentType }) {
            nodes[teammate].status = .running
            incarnations[id] = nodes[teammate].id
            return Outcome(changed: true)
        }
        let key = PendingKey(planner: planner, agentType: agentType)
        let prompt = pending[key]?.first
        if prompt != nil { pending[key]?.removeFirst() }
        nodes.append(NativeSubagent(id: id, agentType: agentType, plannerID: planner, sourceAgent: sourceAgent,
                                    prompt: prompt?.description ?? prompt?.prompt, startedAt: nowMs))
        return Outcome(changed: true)
    }

    private mutating func stop(_ hook: SubagentHook, nowMs: UInt64) -> Outcome {
        guard let id = hook.agentID else { return .none }
        let nodeID = incarnations[id] ?? id
        guard let index = index(of: nodeID) else { return .none }
        nodes[index].status = nodes[index].kind == .teammate ? .idle : .done
        nodes[index].endedAt = nowMs
        if let message = hook.lastAssistantMessage { nodes[index].result = message }
        incarnations[id] = nil
        guard let path = hook.transcriptPath else { return Outcome(changed: true) }
        transcripts[nodeID] = path
        return Outcome(changed: true, transcript: Transcript(nodeID: nodeID, path: path))
    }

    private mutating func postToolUse(_ hook: SubagentHook, planner: String?, sourceAgent: String, nowMs: UInt64) -> Outcome {
        if hook.toolName == "Bash", hook.runInBackground {
            guard let task = hook.response["backgroundTaskId"] else { return .none }
            let id = "background:" + task
            guard index(of: id) == nil else { return .none }
            nodes.append(NativeSubagent(id: id, agentType: "Bash", kind: .background, plannerID: planner,
                                        sourceAgent: sourceAgent, prompt: hook.input["description"] ?? hook.input["command"],
                                        startedAt: nowMs))
            return Outcome(changed: true)
        }
        if hook.toolName == "TaskStop" || hook.toolName == "KillShell" {
            guard let task = hook.input["task_id"] ?? hook.input["shell_id"],
                  let index = index(of: "background:" + task) else { return .none }
            nodes[index].status = .done
            nodes[index].endedAt = nowMs
            if let message = hook.response["message"] { nodes[index].result = message }
            return Outcome(changed: true)
        }
        return .none
    }

    private mutating func preToolUse(_ hook: SubagentHook, planner: String?, sourceAgent: String, nowMs: UInt64) -> Outcome {
        guard let agentID = hook.agentID else {
            guard let tool = hook.toolName, Self.spawnerTools.contains(tool) else { return .none }
            if let name = hook.input["name"], hook.input["team_name"] != nil {
                let id = teammateID(name, planner: planner)
                guard index(of: id) == nil else { return .none }
                nodes.append(NativeSubagent(id: id, agentType: name, kind: .teammate, plannerID: planner,
                                            sourceAgent: sourceAgent, prompt: hook.input["prompt"] ?? hook.input["description"],
                                            startedAt: nowMs))
                return Outcome(changed: true)
            }
            let key = PendingKey(planner: planner, agentType: hook.input["subagent_type"] ?? "general-purpose")
            let queue = (pending[key] ?? []) + [PendingPrompt(description: hook.input["description"], prompt: hook.input["prompt"])]
            pending[key] = Array(queue.suffix(Self.pendingLimit))
            return .none
        }
        guard index(of: incarnations[agentID] ?? agentID) == nil else { return .none }
        nodes.append(NativeSubagent(id: agentID, agentType: hook.agentType ?? "unknown", plannerID: planner,
                                    sourceAgent: sourceAgent, startedAt: nowMs))
        return Outcome(changed: true)
    }

    private mutating func teammateIdle(_ hook: SubagentHook, planner: String?) -> Outcome {
        guard let name = hook.teammateName,
              let index = nodes.firstIndex(where: { $0.kind == .teammate && $0.plannerID == planner && $0.agentType == name }),
              nodes[index].status != .idle else { return .none }
        nodes[index].status = .idle
        return Outcome(changed: true)
    }

    func teammateID(_ name: String, planner: String?) -> String {
        planner.map { "teammate:\($0)/\(name)" } ?? "teammate:" + name
    }
}
