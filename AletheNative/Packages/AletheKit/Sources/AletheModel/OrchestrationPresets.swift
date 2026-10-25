import Foundation

extension OrchestrationPreferences {
    public mutating func applyPreset(_ preset: String) {
        guard ["economy", "balanced", "performance"].contains(preset) else { return }
        let scout = OrchestrationRole(name: "scout", agent: "claude", model: "haiku", effort: "low", fallback: "handyman")
        let handyman = OrchestrationRole(name: "handyman", effort: "low", readOnly: true)
        let codexBuilder = OrchestrationRole(name: "codex-builder", effort: "medium")
        let builder = OrchestrationRole(name: "builder", agent: "claude", model: "sonnet", effort: "medium", fallback: "codex-builder")
        let expert = OrchestrationRole(name: "expert", agent: "claude", model: "opus", effort: "high", fallback: "builder")
        let owned: [OrchestrationRole]
        if case "economy" = preset { owned = [scout, handyman, .init(name: "builder", effort: "medium", fallback: "scout")] }
        else if case "performance" = preset { owned = [builder, codexBuilder, expert] }
        else { owned = [scout, handyman, builder, codexBuilder, expert] }
        roles = owned + roles.filter { current in !owned.contains { $0.name == current.name } }
        func rule(_ role: String, kinds: [String] = [], efforts: [String] = [], gate: Int? = nil) -> OrchestrationRoutingRule {
            var rule = OrchestrationRoutingRule(role: role)
            rule.kinds = kinds; rule.efforts = efforts
            if let gate { var quota = OrchestrationQuotaGate(); quota.window = "opus"; quota.below = gate; rule.gates = [quota] }
            return rule
        }
        if case "economy" = preset { routing.rules = [rule("scout", kinds: ["research", "scrap", "docs"]), rule("scout",
            efforts: ["light"]), rule("handyman", kinds: ["review"]), rule("builder", efforts: ["standard", "deep"])] }
        else if case "performance" = preset { routing.rules = [rule("builder", efforts: ["light"]), rule("expert",
            efforts: ["deep"], gate: 80), rule("builder")] }
        else { routing.rules = [rule("scout", kinds: ["research", "scrap", "docs"]), rule("scout", efforts: ["light"]),
            rule("handyman", kinds: ["review"]), rule("expert", efforts: ["deep"], gate: 50), rule("builder")] }
        routing.preset = preset
        self = normalized
    }
}
