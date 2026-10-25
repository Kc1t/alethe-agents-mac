import Foundation

public enum SecretRedactor {
    public static let placeholder = "<redacted>"

    private static let secretKey =
        "[A-Za-z0-9_.-]*(?:token|secret|passw(?:or)?d|pwd|api[_-]?key|apikey|access[_-]?key|private[_-]?key|"
        + "credential|authorization|cookie)[A-Za-z0-9_.-]*"

    private static let rules: [(regex: NSRegularExpression, template: String)] = [
        (#"(://[^/\s:@]+):[^/\s@]+@"#, "$1:\(placeholder)@"),
        (#"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{6,}"#, "$1 \(placeholder)"),
        (#"(?i)(\#(secretKey)["']?\s*[:=]\s*["']?)[^\s"',;&}]+"#, "$1\(placeholder)"),
        (#"(?i)(--\#(secretKey)\s+)[^\s"']+"#, "$1\(placeholder)"),
        (#"(?i)([?&]pair=)[^\s"'&#]+"#, "$1\(placeholder)"),
        (#"\bsk-[A-Za-z0-9_-]{16,}"#, placeholder),
        (#"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"#, placeholder),
        (#"\bxox[abposr]-[A-Za-z0-9-]{10,}"#, placeholder),
        (#"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#, placeholder),
        (#"\bAIza[0-9A-Za-z_-]{35}"#, placeholder),
        (#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#, placeholder),
    ].map { pattern, template in
        (try! NSRegularExpression(pattern: pattern), template)
    }

    public static func redact(_ text: String) -> String {
        var result = text
        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.template)
        }
        return result
    }
}
