import Foundation

public struct ProjectSettingsFile: Equatable, Sendable {
    public var name: String?
    public var color: ProjectColor?
    public var autoWorktree: Bool?
    public var worktreeMode: ProjectWorktreeMode?
    public var layoutMode: PaneLayoutMode?
    public var githubURL: String?

    public enum Failure: Error, Equatable, Sendable {
        case unreadable
        case noSettings
    }

    public enum Change: Hashable, Sendable {
        case name(from: String, to: String)
        case color(from: ProjectColor, to: ProjectColor)
        case autoWorktree(from: Bool, to: Bool)
        case worktreeMode(from: ProjectWorktreeMode, to: ProjectWorktreeMode)
        case layoutMode(from: PaneLayoutMode, to: PaneLayoutMode)
        case githubURL(from: String?, to: String?)
    }

    public init(name: String? = nil, color: ProjectColor? = nil, autoWorktree: Bool? = nil,
                worktreeMode: ProjectWorktreeMode? = nil, layoutMode: PaneLayoutMode? = nil, githubURL: String? = nil) {
        self.name = name
        self.color = color
        self.autoWorktree = autoWorktree
        self.worktreeMode = worktreeMode
        self.layoutMode = layoutMode
        self.githubURL = githubURL
    }

    public init(project: Project) {
        self.init(name: project.name, color: project.color, autoWorktree: project.usesAutoWorktree,
                  worktreeMode: project.effectiveWorktreeMode, layoutMode: project.layout, githubURL: project.githubURL)
    }

    public init(data: Data) throws(Failure) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw .unreadable }
        name = (object["name"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        color = TauriImport.projectColor(object["color"])
        autoWorktree = object["autoWorktree"] as? Bool
        worktreeMode = (object["worktreeMode"] as? String).flatMap(ProjectWorktreeMode.init(rawValue:))
        layoutMode = (object["layoutMode"] as? String).flatMap(PaneLayoutMode.init(rawValue:))
        githubURL = (object["githubUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard name != nil || color != nil || autoWorktree != nil || worktreeMode != nil || layoutMode != nil
                || githubURL != nil else { throw .noSettings }
    }

    public func data() throws -> Data {
        var object: [String: Any] = ["terminals": [Any]()]
        object["name"] = name
        object["color"] = color?.rawValue
        object["autoWorktree"] = autoWorktree
        object["worktreeMode"] = worktreeMode?.rawValue
        object["layoutMode"] = layoutMode?.rawValue
        object["githubUrl"] = githubURL
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    public func changes(to project: Project) -> [Change] {
        var changes: [Change] = []
        if let name, name != project.name { changes.append(.name(from: project.name, to: name)) }
        if let color, color != project.color { changes.append(.color(from: project.color, to: color)) }
        if let autoWorktree, autoWorktree != project.usesAutoWorktree {
            changes.append(.autoWorktree(from: project.usesAutoWorktree, to: autoWorktree))
        }
        if let worktreeMode, worktreeMode != project.effectiveWorktreeMode {
            changes.append(.worktreeMode(from: project.effectiveWorktreeMode, to: worktreeMode))
        }
        if let layoutMode, layoutMode != project.layout { changes.append(.layoutMode(from: project.layout, to: layoutMode)) }
        if let githubURL, githubURL != project.githubURL { changes.append(.githubURL(from: project.githubURL, to: githubURL)) }
        return changes
    }

    public func apply(to project: inout Project) {
        if let name { project.name = name }
        if let color { project.color = color }
        if let autoWorktree { project.autoWorktree = autoWorktree ? true : nil }
        if let worktreeMode { project.worktreeMode = worktreeMode == .gitWorktree ? nil : worktreeMode }
        if let layoutMode { project.activeArrangement.layoutMode = layoutMode == .auto ? nil : layoutMode }
        if let githubURL { project.githubURL = githubURL }
    }

    public static func suggestedFileName(for project: Project) -> String {
        let base = String(project.name.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "-" })
        return "\(base.isEmpty ? "project" : base).alethe-project.json"
    }
}
