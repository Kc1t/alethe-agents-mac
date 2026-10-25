import Foundation

public enum ModelDiscovery {
    private static let modelFlags: [AgentKind: String] = [
        .claude: "--model", .codex: "--model", .opencode: "--model", .cursor: "--model", .copilot: "--model",
    ]

    public static func modelFlag(for kind: AgentKind) -> String? {
        modelFlags[kind]
    }

    public static func listsModels(_ kind: AgentKind) -> Bool {
        kind == .cursor || kind == .opencode || kind == .antigravity
    }

    public static let claudeAliases = ["sonnet", "opus", "haiku", "opusplan"]

    public static func isValidModelID(_ id: String) -> Bool {
        let lower = id.lowercased()
        let prose = ["usage", "could", "error", "failed", "let", "flags", "available"]
        return id.count >= 3 && !id.hasPrefix("-") && !id.hasPrefix("#") && !id.contains(" ")
            && !prose.contains { lower.hasPrefix($0) }
    }

    public static func parse(_ output: String) -> [String] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let id = line.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
            return isValidModelID(id) && seen.insert(id).inserted ? id : nil
        }
    }

    public static func discover(_ kind: AgentKind, executable: String?) async -> [String] {
        guard modelFlag(for: kind) != nil || listsModels(kind) else { return [] }
        if kind == .claude { return claudeAliases }
        guard listsModels(kind), let executable,
              let output = await CLIOutput.run(executable, ["models"], timeout: .seconds(8)) else { return [] }
        return parse(output)
    }

    public static func arguments(_ base: [String], model: String, for kind: AgentKind) -> [String] {
        guard let flag = modelFlag(for: kind) else { return base }
        var clean: [String] = []
        var index = 0
        while index < base.count {
            if base[index] == flag || base[index] == "-m" { index += 2; continue }
            if base[index].hasPrefix(flag + "=") { index += 1; continue }
            clean.append(base[index])
            index += 1
        }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? clean : clean + [flag, trimmed]
    }
}
