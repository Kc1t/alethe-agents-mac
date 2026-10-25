import AletheFoundation
import Foundation

public struct PromptHistoryDocument: VersionedDocument, Hashable {
    public static let currentVersion = 1
    public static let migrations: [Int: @Sendable (inout JSONObject) throws -> Void] = [:]
    public static let initial = PromptHistoryDocument()

    public var schemaVersion: Int
    public var histories: [String: [String]]

    public init(schemaVersion: Int = currentVersion, histories: [String: [String]] = [:]) {
        self.schemaVersion = schemaVersion
        self.histories = histories
    }

    public mutating func prune(keeping tabs: Set<TabID>) {
        let kept = Set(tabs.map(\.rawValue))
        histories = histories.filter { kept.contains($0.key) }
    }
}

public typealias PromptHistoryModel = DocumentModel<PromptHistoryDocument>
