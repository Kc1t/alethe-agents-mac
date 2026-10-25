import Foundation

public struct ProjectMarker: Equatable, Sendable {
    public static let relativePath = ".alethe/project.json"

    public var name: String
    public var color: ProjectColor?
    public var autoWorktree: Bool?
    public var worktreeMode: ProjectWorktreeMode?
    public var layoutMode: PaneLayoutMode?
    public var githubURL: String?
    let terminals: Data

    public init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String,
              let terminals = object["terminals"] as? [Any],
              let terminalsData = try? JSONSerialization.data(withJSONObject: terminals) else { return nil }
        self.name = name
        color = TauriImport.projectColor(object["color"])
        autoWorktree = object["autoWorktree"] as? Bool
        worktreeMode = (object["worktreeMode"] as? String).flatMap(ProjectWorktreeMode.init(rawValue:))
        layoutMode = (object["layoutMode"] as? String).flatMap(PaneLayoutMode.init(rawValue:))
        githubURL = (object["githubUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.terminals = terminalsData
    }

    public static func url(in folder: URL) -> URL {
        folder.appending(path: relativePath, directoryHint: .notDirectory)
    }

    public static func read(folder: URL) -> ProjectMarker? {
        (try? Data(contentsOf: url(in: folder))).flatMap(ProjectMarker.init(data:))
    }

    private var terminalObjects: [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: terminals)) as? [[String: Any]] ?? []
    }

    public var agents: [String] {
        terminalObjects.flatMap { terminal -> [String] in
            guard (terminal["kind"] as? String ?? "terminal") == "terminal" else { return [] }
            return (terminal["tabs"] as? [[String: Any]] ?? []).map { $0["type"] as? String ?? "shell" }
        }
    }

    public func panes(folder: String, agents: Set<String>) -> [Pane] {
        let context = TauriImport.Context(agents: agents, themes: [], includePreferences: false)
        var report = TauriImport.Report()
        return terminalObjects.compactMap { terminal in
            guard (terminal["kind"] as? String ?? "terminal") == "terminal" else { return nil }
            return TauriImport.pane(from: terminal, folder: folder, project: name, context: context, report: &report)
                .map { pane in
                    var pane = pane
                    pane.gridID = nil
                    for index in pane.tabs.indices { pane.tabs[index].sessionID = nil }
                    return pane
                }
        }
    }

    public func apply(to project: inout Project, agents knownAgents: Set<String>) {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { project.name = name }
        if let color { project.color = color }
        project.autoWorktree = autoWorktree == true ? true : nil
        project.worktreeMode = worktreeMode == .gitWorktree ? nil : worktreeMode
        project.layoutMode = layoutMode == .auto ? nil : layoutMode
        if let githubURL { project.githubURL = githubURL }
        if project.panes.isEmpty { project.panes = panes(folder: project.folder, agents: knownAgents) }
    }

    public static func data(for project: Project, merging existing: Data? = nil) throws -> Data {
        var object = existing.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        let folder = project.folder
        if object["id"] as? String == nil { object["id"] = project.id.rawValue }
        object["name"] = project.name
        object["color"] = project.color.rawValue
        object["defaultCwd"] = folder
        if object["groupId"] == nil { object["groupId"] = NSNull() }
        if object["collapsed"] == nil { object["collapsed"] = false }
        object["layoutMode"] = project.layout.rawValue
        object["createdAt"] = Int((project.createdAt.timeIntervalSince1970 * 1000).rounded())
        object["autoWorktree"] = project.autoWorktree == true ? true : nil
        object["worktreeMode"] = project.worktreeMode?.rawValue
        object["githubUrl"] = project.githubURL
        object["terminals"] = project.panes.filter(\.content.isTerminal).map { terminal($0, folder: folder) }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func terminal(_ pane: Pane, folder: String) -> [String: Any] {
        let tabs: [[String: Any]] = pane.tabs.map { tab in
            let cwd = tab.worktreeAgentID == nil ? (tab.workingDirectory ?? folder) : folder
            return [
                "id": tab.id.rawValue,
                "type": tab.agent,
                "name": tab.title ?? tab.agent,
                "cwd": cwd,
                "ptyId": NSNull(),
                "extraArgs": tab.extraArguments,
            ]
        }
        return [
            "id": pane.id.rawValue,
            "kind": "terminal",
            "name": pane.activeTab?.title ?? pane.activeTab?.agent ?? "terminal",
            "cwd": folder,
            "tabs": tabs,
            "activeTabId": (pane.activeTabID ?? pane.tabs.first?.id)?.rawValue ?? "",
            "disabled": false,
            "laneVisible": NSNull(),
        ]
    }

    public static func write(_ project: Project) throws {
        let folder = URL(filePath: project.folder, directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }
        let file = url(in: folder)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try data(for: project, merging: try? Data(contentsOf: file))
        try data.write(to: file, options: .atomic)
    }
}
