import Foundation

public enum SidebarDropEdge: Equatable, Sendable { case before, after, inside }

extension WorkspaceDocument {
    public mutating func dropProject(_ id: ProjectID, beside target: ProjectID, edge: SidebarDropEdge) {
        guard id != target, let location = location(of: target) else { return }
        let ids: [ProjectID]
        if case .ungrouped = location { ids = ungroupedProjectIDs } else {
            guard case .group(let group) = location else {
                preconditionFailure("Unexpected enum case")
            }
            ids = self.group(group)?.projectIDs ?? []
        }
        guard let index = ids.firstIndex(of: target) else { return }
        moveProject(id, to: location, at: index + (edge == .after ? 1 : 0))
    }

    public mutating func dropGroup(_ id: GroupID, beside target: GroupID, edge: SidebarDropEdge) {
        guard id != target, let destination = group(target) else { return }
        if edge == .inside {
            guard group(id)?.parentID != target else { return }
            moveGroup(id, toParent: target, at: Int.max)
            return
        }
        let siblings = childGroups(of: destination.parentID)
        guard let targetIndex = siblings.firstIndex(where: { $0.id == target }) else { return }
        var index = targetIndex + (edge == .after ? 1 : 0)
        if let source = siblings.firstIndex(where: { $0.id == id }), source < index { index -= 1 }
        moveGroup(id, toParent: destination.parentID, at: index)
    }
}
