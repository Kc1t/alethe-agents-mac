import Foundation

public enum ProjectGridTag {}
public typealias ProjectGridID = Identifier<ProjectGridTag>

public struct PaneArrangement: Hashable, Sendable {
    public var layoutMode: PaneLayoutMode?
    public var gridLayout: CustomGrid?
    public var gridLayoutHistory: [CustomGridHistoryEntry]?

    public init(layoutMode: PaneLayoutMode? = nil, gridLayout: CustomGrid? = nil,
                gridLayoutHistory: [CustomGridHistoryEntry]? = nil) {
        self.layoutMode = layoutMode
        self.gridLayout = gridLayout
        self.gridLayoutHistory = gridLayoutHistory
    }
}

public struct ProjectGrid: Codable, Hashable, Sendable, Identifiable {
    public var id: ProjectGridID
    public var name: String
    public var layoutMode: PaneLayoutMode?
    public var gridLayout: CustomGrid?
    public var gridLayoutHistory: [CustomGridHistoryEntry]?

    public init(id: ProjectGridID = .make(), name: String, layoutMode: PaneLayoutMode? = nil,
                gridLayout: CustomGrid? = nil, gridLayoutHistory: [CustomGridHistoryEntry]? = nil) {
        self.id = id
        self.name = name
        self.layoutMode = layoutMode
        self.gridLayout = gridLayout
        self.gridLayoutHistory = gridLayoutHistory
    }
}

extension Project {
    public var namedGrids: [ProjectGrid] { grids ?? [] }

    public var shownGridID: ProjectGridID? {
        activeGridID.flatMap { id in namedGrids.contains { $0.id == id } ? id : nil }
    }

    public var visiblePanes: [Pane] {
        let shown = shownGridID
        return panes.filter { pane in pane.gridID.flatMap { id in namedGrids.contains { $0.id == id } ? id : nil } == shown }
    }

    public func panes(in grid: ProjectGridID?) -> [Pane] {
        panes.filter { $0.gridID == grid || (grid == nil && $0.gridID.map { id in !namedGrids.contains { $0.id == id } } == true) }
    }

    public var activeArrangement: PaneArrangement {
        get {
            if let id = shownGridID, let grid = namedGrids.first(where: { $0.id == id }) {
                return PaneArrangement(layoutMode: grid.layoutMode, gridLayout: grid.gridLayout,
                                       gridLayoutHistory: grid.gridLayoutHistory)
            }
            return PaneArrangement(layoutMode: layoutMode, gridLayout: gridLayout, gridLayoutHistory: gridLayoutHistory)
        }
        set {
            if let id = shownGridID, let index = grids?.firstIndex(where: { $0.id == id }) {
                grids?[index].layoutMode = newValue.layoutMode
                grids?[index].gridLayout = newValue.gridLayout
                grids?[index].gridLayoutHistory = newValue.gridLayoutHistory
            } else {
                layoutMode = newValue.layoutMode
                gridLayout = newValue.gridLayout
                gridLayoutHistory = newValue.gridLayoutHistory
            }
        }
    }

    public var weightsKey: String {
        shownGridID.map { "\(id.rawValue):\($0.rawValue)" } ?? id.rawValue
    }

    public func gridName(_ id: ProjectGridID?) -> String? {
        id.flatMap { id in namedGrids.first { $0.id == id }?.name }
    }
}

extension WorkspaceDocument {
    public enum GridNameProblem: Error, Equatable, Sendable {
        case empty, taken, reserved
    }

    public static let reservedGridNames: Set<String> = ["main", "principal", "default", "padrão"]

    public func gridNameProblem(_ name: String, in projectID: ProjectID, except: ProjectGridID? = nil) -> GridNameProblem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let key = trimmed.lowercased()
        if Self.reservedGridNames.contains(key) { return .reserved }
        let taken = project(projectID)?.namedGrids.contains { $0.id != except && $0.name.lowercased() == key } ?? false
        return taken ? .taken : nil
    }

    @discardableResult
    public mutating func createGrid(named name: String, in projectID: ProjectID) -> ProjectGridID? {
        guard project(projectID) != nil, gridNameProblem(name, in: projectID) == nil else { return nil }
        let grid = ProjectGrid(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        updateProject(projectID) { project in
            project.grids = project.namedGrids + [grid]
            project.activeGridID = grid.id
        }
        open(projectID)
        return grid.id
    }

    public mutating func renameGrid(_ gridID: ProjectGridID, in projectID: ProjectID, to name: String) {
        guard gridNameProblem(name, in: projectID, except: gridID) == nil else { return }
        updateProject(projectID) { project in
            guard let index = project.grids?.firstIndex(where: { $0.id == gridID }) else { return }
            project.grids?[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public mutating func activateGrid(_ gridID: ProjectGridID?, in projectID: ProjectID) {
        guard let project = project(projectID), gridID == nil || project.namedGrids.contains(where: { $0.id == gridID }) else { return }
        if project.activeGridID != gridID { updateProject(projectID) { $0.activeGridID = gridID } }
        open(projectID)
        if let focused = workspace.focusedPaneID, self.pane(focused)?.project.id == projectID,
           !(self.project(projectID)?.visiblePanes.contains { $0.id == focused } ?? false) {
            workspace.focusedPaneID = self.project(projectID)?.visiblePanes.first?.id
        }
        if let isolated = workspace.isolatedPaneID, self.pane(isolated)?.project.id == projectID { workspace.isolatedPaneID = nil }
    }

    public mutating func movePane(_ paneID: PaneID, toGrid gridID: ProjectGridID?) {
        guard let (project, pane) = pane(paneID), pane.gridID != gridID,
              gridID == nil || project.namedGrids.contains(where: { $0.id == gridID }) else { return }
        updateProject(project.id) { project in
            if var grids = project.grids {
                for index in grids.indices { grids[index].gridLayout?.cells.removeValue(forKey: paneID.rawValue) }
                project.grids = grids
            }
            project.gridLayout?.cells.removeValue(forKey: paneID.rawValue)
        }
        updatePane(paneID) { $0.gridID = gridID }
        if workspace.isolatedPaneID == paneID { workspace.isolatedPaneID = nil }
        if workspace.focusedPaneID == paneID { workspace.focusedPaneID = self.project(project.id)?.visiblePanes.first?.id }
    }

    public mutating func deleteGrid(_ gridID: ProjectGridID, in projectID: ProjectID, closingPanes: Bool) {
        guard let project = project(projectID), project.namedGrids.contains(where: { $0.id == gridID }) else { return }
        for pane in project.panes where pane.gridID == gridID {
            if closingPanes { closePane(pane.id) } else { updatePane(pane.id) { $0.gridID = nil } }
        }
        updateProject(projectID) { project in
            project.grids = project.namedGrids.filter { $0.id != gridID }
            if project.grids?.isEmpty == true { project.grids = nil }
            if project.activeGridID == gridID { project.activeGridID = nil }
        }
        workspace.gridWeights.removeValue(forKey: "\(projectID.rawValue):\(gridID.rawValue)")
    }

    mutating func reveal(_ paneID: PaneID) {
        guard let (project, pane) = pane(paneID) else { return }
        let grid = pane.gridID.flatMap { id in project.namedGrids.contains { $0.id == id } ? id : nil }
        if project.shownGridID != grid { updateProject(project.id) { $0.activeGridID = grid } }
    }
}
