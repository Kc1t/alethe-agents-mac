import Foundation
import AletheAgents
import AletheIntegrations

extension OrchestratorCore {
    public func setAgentFitness(_ agent: String, _ fitness: AgentFitness) {
        fitnessReadings[agent] = fitness
        if let deferredPrompts { Task { await deferredPrompts.tick() } }
    }

    @discardableResult
    public func setAgentFitness(from usage: ProviderUsage) -> AgentFitness? {
        guard let reading = AgentFitness(usage) else { return nil }
        setAgentFitness(usage.agent.rawValue, reading)
        return reading
    }

    public func agentFitness() -> [String: AgentFitness] { fitnessReadings }

    func withFitness(_ result: OrderedJSON, tool name: String, arguments: OrderedJSONObject) -> OrderedJSON {
        let routing = FitnessRouting(fitnessReadings)
        guard let block = routing.block, case .object(var object) = result else { return result }
        if name == "alethe_delegate" {
            let requested = arguments["agent"]?.stringValue ?? WorkerAgent.codex
            if let note = routing.routingNote(requested: requested) {
                let ids = object["jobs"]?.arrayValue?.compactMap { $0.objectValue?["id"]?.stringValue } ?? []
                for id in ids { jobs[id]?.routing = note }
                if !ids.isEmpty { notify() }
            }
            if let hint = routing.headroomHint(requested: requested) {
                object["headroomHint"] = hint
            }
        }
        object["fitness"] = block
        return .object(object)
    }
}
