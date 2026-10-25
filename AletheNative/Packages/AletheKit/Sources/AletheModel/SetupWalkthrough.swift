import Foundation

public enum SetupStep: String, CaseIterable, Codable, Sendable {
    case agents
    case project
    case terminal
    case appearance
}

public struct SetupProgress: Equatable, Sendable {
    public var done: Set<SetupStep>

    public init(document: WorkspaceDocument, agentsFound: Bool, marked: [String]?) {
        var done = Set((marked ?? []).compactMap(SetupStep.init(rawValue:)))
        if agentsFound { done.insert(.agents) }
        if !document.projects.isEmpty { done.insert(.project) }
        if document.projects.contains(where: { $0.panes.contains { $0.content.isTerminal } }) { done.insert(.terminal) }
        self.done = done
    }

    public var count: Int { done.count }
    public var total: Int { SetupStep.allCases.count }
    public var isComplete: Bool { count == total }
}
