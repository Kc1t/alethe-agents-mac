import Foundation
import SQLite3

public struct ModelCost: Hashable, Sendable, Identifiable {
    public var model: String
    public var input: Int = 0
    public var output: Int = 0
    public var cacheRead: Int = 0
    public var cacheWrite5m: Int = 0
    public var cacheWrite1h: Int = 0
    public var costUSD: Double?

    public var id: String { model }
    public var totalTokens: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }

    public init(model: String, input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite5m: Int = 0,
                cacheWrite1h: Int = 0, costUSD: Double? = nil) {
        self.model = model
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.costUSD = costUSD
    }
}

public struct SessionCost: Hashable, Sendable {
    public var byModel: [ModelCost]
    public var costUSD: Double?
    public var model: String?

    public var input: Int { byModel.reduce(0) { $0 + $1.input } }
    public var output: Int { byModel.reduce(0) { $0 + $1.output } }
    public var cacheRead: Int { byModel.reduce(0) { $0 + $1.cacheRead } }
    public var cacheWrite: Int { byModel.reduce(0) { $0 + $1.cacheWrite5m + $1.cacheWrite1h } }
    public var totalTokens: Int { byModel.reduce(0) { $0 + $1.totalTokens } }

    public init(byModel: [ModelCost]) {
        let priced = byModel.map { cost -> ModelCost in
            var cost = cost
            if cost.costUSD == nil { cost.costUSD = ModelPricing.cost(of: cost) }
            return cost
        }
        self.byModel = priced
        let known = priced.compactMap(\.costUSD)
        costUSD = known.isEmpty ? nil : known.reduce(0, +)
        model = priced.max { $0.output < $1.output }?.model
    }
}

public enum ModelPricing {
    public struct Rate: Hashable, Sendable {
        public var family: String
        public var input: Double
        public var output: Double
        public var cacheWrite5m: Double { input * 1.25 }
        public var cacheWrite1h: Double { input * 2 }
        public var cacheRead: Double { input * 0.1 }
    }

    public static let rates = [
        Rate(family: "opus", input: 5, output: 25),
        Rate(family: "sonnet", input: 3, output: 15),
        Rate(family: "haiku", input: 1, output: 5),
    ]

    public static func rate(for model: String) -> Rate? {
        let lower = model.lowercased()
        return rates.first { lower.contains($0.family) }
    }

    public static func cost(of usage: ModelCost) -> Double? {
        guard let rate = rate(for: usage.model) else { return nil }
        let million = 1_000_000.0
        return Double(usage.input) / million * rate.input + Double(usage.output) / million * rate.output
            + Double(usage.cacheRead) / million * rate.cacheRead
            + Double(usage.cacheWrite5m) / million * rate.cacheWrite5m
            + Double(usage.cacheWrite1h) / million * rate.cacheWrite1h
    }
}

public enum SessionCosts {
    public static func claude(transcript path: String) -> SessionCost {
        var models: [String: ModelCost] = [:]
        let usageKey = Data(#""usage""#.utf8)
        JSONLReader.forEachLine(atPath: path) { line in
            guard line.range(of: usageKey) != nil, let object = JSONLReader.object(line),
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { return true }
            let model = message["model"] as? String ?? "unknown"
            var entry = models[model] ?? ModelCost(model: model)
            func tokens(_ key: String, in object: [String: Any]? = nil) -> Int? {
                ((object ?? usage)[key] as? NSNumber)?.intValue
            }
            entry.input += tokens("input_tokens") ?? 0
            entry.output += tokens("output_tokens") ?? 0
            entry.cacheRead += tokens("cache_read_input_tokens") ?? 0
            let creation = usage["cache_creation"] as? [String: Any]
            if let fiveMinutes = tokens("ephemeral_5m_input_tokens", in: creation),
               let oneHour = tokens("ephemeral_1h_input_tokens", in: creation) {
                entry.cacheWrite5m += fiveMinutes
                entry.cacheWrite1h += oneHour
            } else {
                entry.cacheWrite5m += tokens("cache_creation_input_tokens") ?? 0
            }
            models[model] = entry
            return true
        }
        return SessionCost(byModel: models.values.sorted { $0.model < $1.model })
    }

    public static func codex(rollout path: String) -> SessionCost {
        var cost = ModelCost(model: "codex")
        let marker = Data(#""token_count""#.utf8)
        JSONLReader.forEachLine(atPath: path) { line in
            guard line.range(of: marker) != nil, let object = JSONLReader.object(line),
                  let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                  let total = (payload["info"] as? [String: Any])?["total_token_usage"] as? [String: Any] else { return true }
            func tokens(_ key: String) -> Int { (total[key] as? NSNumber)?.intValue ?? 0 }
            cost.input = tokens("input_tokens")
            cost.output = tokens("output_tokens")
            cost.cacheRead = tokens("cached_input_tokens")
            return true
        }
        return SessionCost(byModel: [cost])
    }

    public static func openCode(sessionID: String, database: String) -> SessionCost? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(handle) }
        let query = "SELECT model, tokens_input, tokens_output, tokens_cache_read, tokens_cache_write, cost FROM session WHERE id = ?1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, sessionID, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let rawModel = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        let model = (try? JSONSerialization.jsonObject(with: Data(rawModel.utf8)) as? [String: Any])?["id"] as? String ?? rawModel
        return SessionCost(byModel: [ModelCost(
            model: model.isEmpty ? "opencode" : model,
            input: Int(sqlite3_column_int64(statement, 1)), output: Int(sqlite3_column_int64(statement, 2)),
            cacheRead: Int(sqlite3_column_int64(statement, 3)), cacheWrite5m: Int(sqlite3_column_int64(statement, 4)),
            costUSD: sqlite3_column_double(statement, 5))])
    }

    public static func openCodeDatabase(executable: String?, homeDirectory: String = NSHomeDirectory()) async -> String? {
        if let executable, let answer = await CLIOutput.run(executable, ["db", "path"], timeout: .seconds(5)) {
            let path = answer.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return ["\(homeDirectory)/.local/share/opencode/opencode.db",
                "\(homeDirectory)/Library/Application Support/opencode/opencode.db"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    public static func transcript(_ kind: AgentKind, sessionID: String, cwd: String,
                                  homeDirectory: String = NSHomeDirectory()) -> String? {
        switch kind {
        case .claude:
            let projects = "\(homeDirectory)/.claude/projects"
            let names = Set([cwd, SessionPaths.normalize(cwd)].filter { !$0.isEmpty }.map(ClaudeSessions.projectFolderName(for:)))
            let folders = ((try? FileManager.default.contentsOfDirectory(atPath: projects)) ?? [])
                .filter { folder in names.contains { $0.caseInsensitiveCompare(folder) == .orderedSame } }
            return folders.map { "\(projects)/\($0)/\(sessionID).jsonl" }.first { FileManager.default.fileExists(atPath: $0) }
        case .codex:
            let root = "\(homeDirectory)/.codex/sessions"
            guard let enumerator = FileManager.default.enumerator(atPath: root) else { return nil }
            while let relative = enumerator.nextObject() as? String {
                if relative.hasSuffix("\(sessionID).jsonl") { return "\(root)/\(relative)" }
            }
            return nil
        default:
            return nil
        }
    }

    public static func cost(_ kind: AgentKind, sessionID: String, cwd: String, openCodeExecutable: String?) async -> SessionCost? {
        switch kind {
        case .claude: return transcript(.claude, sessionID: sessionID, cwd: cwd).map { claude(transcript: $0) }
        case .codex: return transcript(.codex, sessionID: sessionID, cwd: cwd).map { codex(rollout: $0) }
        case .opencode:
            guard let database = await openCodeDatabase(executable: openCodeExecutable) else { return nil }
            return openCode(sessionID: sessionID, database: database)
        default: return nil
        }
    }
}
