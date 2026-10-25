import Foundation

public struct MediaItem: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case imageLocal = "image-local"
        case imageURL = "image-url"
        case link
    }

    public var kind: Kind
    public var value: String

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }
}

public enum BoardMedia {
    public static let maxItems = 4

    private static let localPath = regularExpression(pattern: #"(?<![A-Za-z0-9:/~._\-])~?/[^\s"'`/][^\s"'`]*"#)
    private static let url = regularExpression(pattern: #"https?://[^\s"'`)]+"#)
    private static let imageExtension = regularExpression(pattern: #"\.(png|jpe?g|gif|webp|svg)$"#, options: .caseInsensitive)
    private static let trailingPunctuation = regularExpression(pattern: #"[.,;:!?)\]]+$"#)

    private static func regularExpression(
        pattern: String, options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            preconditionFailure("Board media patterns must be valid regular expressions")
        }
        return expression
    }

    public static func extract(_ text: String) -> [MediaItem] {
        var items: [MediaItem] = []
        var seen = Set<String>()

        for raw in matches(localPath, in: text) {
            let value = stripTrailingPunctuation(raw)
            if seen.contains(value) || !isImage(value) { continue }
            seen.insert(value)
            items.append(MediaItem(kind: .imageLocal, value: value))
            if items.count >= maxItems { return items }
        }

        for raw in matches(url, in: text) {
            let value = stripTrailingPunctuation(raw)
            let image = isImage(value)
            let alreadyLinked = !image && text.contains("](\(value))")
            if seen.contains(value) || alreadyLinked { continue }
            seen.insert(value)
            items.append(MediaItem(kind: image ? .imageURL : .link, value: value))
            if items.count >= maxItems { return items }
        }

        return items
    }

    public static func promoted(_ report: String) -> MediaItem? {
        let trimmed = report.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return extract(trimmed).first { $0.kind != .link }
    }

    public static func remaining(_ report: String) -> [MediaItem] {
        let trimmed = report.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var items = extract(trimmed)
        if let promoted = items.firstIndex(where: { $0.kind != .link }) { items.remove(at: promoted) }
        return items
    }

    public static func promotedByJobID(_ jobs: [JobSnapshot]) -> [String: MediaItem] {
        var map: [String: MediaItem] = [:]
        for job in jobs {
            if let item = promoted(job.summary) { map[job.id] = item }
        }
        return map
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func isImage(_ value: String) -> Bool {
        imageExtension.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    private static func stripTrailingPunctuation(_ value: String) -> String {
        let range = NSRange(value.startIndex..., in: value)
        return trailingPunctuation.stringByReplacingMatches(in: value, range: range, withTemplate: "")
    }
}
