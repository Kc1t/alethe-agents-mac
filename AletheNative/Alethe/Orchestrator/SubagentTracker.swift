import AletheAgents
import AletheOrchestrator
import Foundation
import Observation

@Observable
@MainActor
final class SubagentTracker {
    private(set) var ledger = SubagentLedger()
    private(set) var costs: [String: SessionCost] = [:]

    var nodes: [NativeSubagent] { ledger.nodes }

    func jobs(now: Date = Date()) -> [JobSnapshot] {
        NativeSubagents.jobs(ledger.nodes, costs: costs, nowMs: UInt64(max(0, now.timeIntervalSince1970 * 1000)))
    }

    func ingest(_ hook: SubagentHook, planner: String, sourceAgent: String, now: Date = Date()) {
        let outcome = ledger.ingest(hook, planner: planner, sourceAgent: sourceAgent,
                                    nowMs: UInt64(max(0, now.timeIntervalSince1970 * 1000)))
        guard let transcript = outcome.transcript else { return }
        readCost(transcript, sourceAgent: sourceAgent)
    }

    private func readCost(_ transcript: SubagentLedger.Transcript, sourceAgent: String) {
        let path = transcript.path
        guard path.hasPrefix("/"), path.hasSuffix(".jsonl") else { return }
        Task { [weak self] in
            let cost = await Task.detached(priority: .utility) {
                sourceAgent == WorkerAgent.codex ? SessionCosts.codex(rollout: path) : SessionCosts.claude(transcript: path)
            }.value
            guard let self, self.ledger.nodes.contains(where: { $0.id == transcript.nodeID }) else { return }
            self.costs[transcript.nodeID] = cost
        }
    }
}
