import Foundation

public struct RemoteSharedTerminal: Equatable, Sendable {
    public var tab: PaneTab
    public var paneID: PaneID
    public var projectID: ProjectID
    public var cwd: String

    public init(tab: PaneTab, paneID: PaneID, projectID: ProjectID, cwd: String) {
        self.tab = tab
        self.paneID = paneID
        self.projectID = projectID
        self.cwd = cwd
    }
}

extension WorkspaceDocument {
    public var remoteSharedTerminals: [RemoteSharedTerminal] {
        projects.flatMap(remoteSharedTerminals(in:))
    }

    public func remoteSharedTerminals(in project: Project) -> [RemoteSharedTerminal] {
        project.panes.filter(\.isRemoteShared).flatMap { pane in
            pane.tabs.map { tab in
                let folder = tab.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
                return RemoteSharedTerminal(tab: tab, paneID: pane.id, projectID: project.id,
                                            cwd: folder.flatMap { $0.isEmpty ? nil : $0 } ?? project.folder)
            }
        }
    }

    public func groupID(holding project: ProjectID) -> GroupID? {
        if case .group(let id) = location(of: project) { return id }
        return nil
    }

    public mutating func setRemoteShared(_ paneID: PaneID, _ shared: Bool) {
        updatePane(paneID) { pane in
            guard pane.content.isTerminal else { return }
            pane.remoteShared = shared ? true : nil
        }
    }
}
