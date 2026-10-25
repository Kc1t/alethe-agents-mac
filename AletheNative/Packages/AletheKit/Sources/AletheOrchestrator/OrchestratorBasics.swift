import AletheIntegrations
import Foundation

public enum OrchestratorLimits {
    public static let defaultConcurrency = 4
    public static let concurrencyRange = 1...16
    public static let maxWaitMs: UInt64 = 600_000
    public static let defaultCheckWaitMs: UInt64 = 300_000
    public static let replyLimit = 16_000
    public static let defaultJobTimeoutMs: UInt64 = 900_000
    public static let parkedLimit = 4
    public static let summaryLimit = 1200
    public static let firstRequestID = 10
}

public enum WorkerAgent {
    public static let codex = "codex"
    public static let claude = "claude"
}

public enum JobStatus: String, Hashable, Sendable, CaseIterable, Codable {
    case queued
    case running
    case blocked
    case done
    case failed
    case cancelled
    case released
    case interrupted

    public var settled: Bool {
        [JobStatus.done, .failed, .cancelled, .released, .interrupted].contains(self)
    }
}

public struct Planner: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var agent: String

    public init(id: String, label: String, agent: String) {
        self.id = id
        self.label = label
        self.agent = agent
    }

    public var json: OrderedJSON {
        ["id": .string(id), "label": .string(label), "agent": .string(agent)]
    }

    public init?(json: OrderedJSON) {
        guard let object = json.objectValue, let id = object["id"]?.stringValue else { return nil }
        self.init(id: id, label: object["label"]?.stringValue ?? id, agent: object["agent"]?.stringValue ?? "")
    }
}

public struct Delivery: Hashable, Sendable {
    public var sequence: UInt64
    public var kind: String
    public var jobID: String
    public var outcome: String?
    public var text: String

    public init(sequence: UInt64, kind: String, jobID: String, outcome: String?, text: String) {
        self.sequence = sequence
        self.kind = kind
        self.jobID = jobID
        self.outcome = outcome
        self.text = text
    }

    public var json: OrderedJSON {
        [
            "seq": .unsigned(sequence),
            "type": .string(kind),
            "jobId": .string(jobID),
            "outcome": .optional(outcome),
            "text": .string(text),
        ]
    }
}

public struct Launcher: Hashable, Sendable {
    public var kind: String
    public var program: URL
    public var arguments: [String]
    public var environment: [String: String]

    public init(kind: String, program: URL, arguments: [String], environment: [String: String] = [:]) {
        self.kind = kind
        self.program = program
        self.arguments = arguments
        self.environment = environment
    }
}

public enum OrchestratorID {
    public static func job(_ number: UInt64) -> String { "job-" + padded(number) }
    public static func run(_ number: UInt64) -> String { "run-" + padded(number) }

    public static func trailingNumber(_ id: String) -> UInt64 {
        let tail = id.split(separator: "-", omittingEmptySubsequences: false).last ?? ""
        return UInt64(tail) ?? 0
    }

    private static func padded(_ number: UInt64) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }
}

public func orchestratorTail(_ text: String, limit: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let scalars = trimmed.unicodeScalars
    guard scalars.count > limit else { return trimmed }
    var result = String.UnicodeScalarView()
    result.append(contentsOf: scalars.suffix(limit))
    return String(result)
}

public enum TokenCounts {
    public static let keys = ["totalTokens", "inputTokens", "outputTokens", "cachedInputTokens", "cacheCreationInputTokens"]

    public static func claude(usage: OrderedJSON) -> OrderedJSON {
        let input = value(usage, "input_tokens")
        let output = value(usage, "output_tokens")
        let cached = value(usage, "cache_read_input_tokens")
        let cacheCreation = value(usage, "cache_creation_input_tokens")
        let total = input.addingSaturated(output).addingSaturated(cached).addingSaturated(cacheCreation)
        return [
            "totalTokens": .unsigned(total),
            "inputTokens": .unsigned(input),
            "outputTokens": .unsigned(output),
            "cachedInputTokens": .unsigned(cached),
            "cacheCreationInputTokens": .unsigned(cacheCreation),
        ]
    }

    public static func adding(_ total: OrderedJSON, _ turn: OrderedJSON) -> OrderedJSON {
        .object(OrderedJSONObject(keys.map { key in
            (key, .unsigned(value(total, key).addingSaturated(value(turn, key))))
        }))
    }

    static func value(_ json: OrderedJSON, _ key: String) -> UInt64 {
        json.objectValue?[key]?.uint64Value ?? 0
    }
}

extension UInt64 {
    func addingSaturated(_ other: UInt64) -> UInt64 {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? .max : sum
    }
}

extension OrderedJSON {
    static func optional(_ value: String?) -> OrderedJSON { value.map(OrderedJSON.string) ?? .null }
    static func optional(_ value: UInt64?) -> OrderedJSON { value.map(OrderedJSON.unsigned) ?? .null }
    static func optional(_ value: Double?) -> OrderedJSON { value.map(OrderedJSON.double) ?? .null }
    static func optional(_ value: OrderedJSON?) -> OrderedJSON { value ?? .null }

    var nonNull: OrderedJSON? {
        if case .null = self { return nil }
        return self
    }
}
