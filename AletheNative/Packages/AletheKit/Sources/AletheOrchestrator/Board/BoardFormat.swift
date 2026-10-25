import Foundation
import AletheIntegrations

public enum BoardFormat {
    public static func elapsed(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite else { return nil }
        let whole = Int(seconds.rounded(.down))
        if whole < 60 { return "\(whole)s" }
        let rest = whole % 60
        return "\(whole / 60)m \(rest < 10 ? "0" : "")\(rest)s"
    }

    public static func tokens(_ total: Double?) -> String? {
        guard let total, total != 0, total.isFinite else { return nil }
        if total < 1000 { return jsNumber(total) }
        if total < 10_000 {
            let tenths = Int(jsRound(total / 100))
            return "\(tenths / 10).\(tenths % 10)k"
        }
        return jsNumber(jsRound(total / 1000)) + "k"
    }

    public static func contextShare(_ job: JobSnapshot) -> Int? {
        guard let used = totalTokens(job), used != 0,
              let window = job.tokens?["modelContextWindow"]?.doubleValue, window != 0
        else { return nil }
        return min(100, Int(jsRound(used / window * 100)))
    }

    public static func totalTokens(_ job: JobSnapshot) -> Double? {
        job.tokens?["total"]?["totalTokens"]?.doubleValue
    }

    public static func latestLine(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty } ?? ""
    }
}

private extension OrderedJSON {
    subscript(key: String) -> OrderedJSON? { objectValue?[key] }
}

func jsRound(_ value: Double) -> Double {
    (value + 0.5).rounded(.down)
}

func jsNumber(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
    return String(value)
}
