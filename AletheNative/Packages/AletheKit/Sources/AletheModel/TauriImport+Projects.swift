import AletheFoundation
import Foundation

extension TauriImport {
    static func importProjects(_ file: File, into workspace: inout WorkspaceDocument, groupIDs: [String: GroupID],
                                       context: Context, report: inout Report) {
        let existingFolders = Set(workspace.projects.map { normalizedFolder($0.folder) })
        let (location, order, byID) = projectOrder(file)

        for projectID in order {
            guard let project = byID[projectID] else { continue }
            importProject(project, location: location[projectID] ?? nil, groupIDs: groupIDs,
                          existingFolders: existingFolders, workspace: &workspace, context: context, report: &report)
        }
    }

    private static func projectOrder(_ file: File)
        -> ([String: String?], [String], [String: [String: Any]]) {
        var location: [String: String?] = [:]
        var order: [String] = []
        for group in file.groups {
            guard let groupID = group["id"] as? String else { continue }
            for projectID in group["projectIds"] as? [String] ?? [] where location[projectID] == nil {
                location[projectID] = .some(groupID)
                order.append(projectID)
            }
        }
        for projectID in file.ungroupedOrder where location[projectID] == nil {
            location[projectID] = .some(nil)
            order.append(projectID)
        }
        let byID = Dictionary(file.projects.compactMap { p in (p["id"] as? String).map { ($0, p) } },
                              uniquingKeysWith: { first, _ in first })
        for project in file.projects {
            guard let id = project["id"] as? String, location[id] == nil else { continue }
            location[id] = .some(project["groupId"] as? String)
            order.append(id)
        }

        return (location, order, byID)
    }

    private static func importProject(_ project: [String: Any], location: String?, groupIDs: [String: GroupID],
                                      existingFolders: Set<String>, workspace: inout WorkspaceDocument,
                                      context: Context, report: inout Report) {
            let name = (project["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Project"
            if project["archived"] as? Bool == true {
                report.skipped.append(.projectArchived(project: name))
                return
            }
            let terminals = project["terminals"] as? [[String: Any]] ?? []
            guard let folder = folder(of: project, terminals: terminals) else {
                report.skipped.append(.projectWithoutFolder(project: name))
                return
            }
            if existingFolders.contains(normalizedFolder(folder)) {
                report.skipped.append(.projectAlreadyAdded(project: name))
                return
            }
            let place = location.flatMap { groupIDs[$0] }.map { ProjectLocation.group($0) } ?? .ungrouped
            let created = workspace.addProject(name: name, folder: folder,
                                               color: projectColor(project["color"]) ?? .blue, in: place)
            workspace.updateProject(created) { $0.iconUrl = project["iconUrl"] as? String }
            report.projects += 1
            let panes = importedPanes(terminals, folder: folder, project: name, context: context, report: &report)
            if let createdAt = (project["createdAt"] as? Double).map({ Date(timeIntervalSince1970: $0 / 1000) }) {
                workspace.updateProject(created) { $0.createdAt = createdAt }
            }
            configureProject(created, from: project, panes: panes, in: &workspace)
            report.panes += panes.count
            report.tabs += panes.reduce(0) { $0 + $1.tabs.count }
    }

    private static func importedPanes(_ terminals: [[String: Any]], folder: String, project name: String,
                                      context: Context, report: inout Report) -> [Pane] {
            var panes: [Pane] = []
            for terminal in terminals {
                if let kind = terminal["kind"] as? String, kind != "terminal" {
                    if kind == PaneContent.Kind.orchestrator.rawValue { panes.append(orchestratorPane(from: terminal)) }
                    else if kind == "graphify" || kind == "diff" {
                        var imported = orchestratorPane(from: terminal)
                        imported.content = kind == "graphify" ? .graphify
                            : .diff(path: terminal["filePath"] as? String, staged: terminal["staged"] as? Bool ?? false)
                        panes.append(imported)
                    } else if ["image", "video", "markdown"].contains(kind), let path = terminal["filePath"] as? String {
                        var imported = orchestratorPane(from: terminal)
                        if case "image" = kind { imported.content = .image(path: path) }
                        else if case "video" = kind { imported.content = .video(path: path) }
                        else { imported.content = .markdown(path: path) }
                        panes.append(imported)
                    } else {
                        report.skipped.append(.paneKind(project: name, kind: kind))
                    }
                    continue
                }
                if let pane = pane(from: terminal, folder: folder, project: name, context: context, report: &report) { panes.append(pane) }
            }
        return panes
    }

    private static func configureProject(_ created: ProjectID, from project: [String: Any], panes: [Pane],
                                         in workspace: inout WorkspaceDocument) {
            workspace.updateProject(created) { target in
                target.panes = panes
                if let raw = project["paneGroups"], JSONSerialization.isValidJSONObject(raw),
                   let data = try? JSONSerialization.data(withJSONObject: raw) {
                    target.paneGroups = try? JSONDecoder().decode([PaneGroup].self, from: data)
                    target.reconcilePaneGroups()
                }
            }
            workspace.updateProject(created) {
                $0.validationCommands = project["validationCommands"] as? [String]
                $0.healthCheckCommand = project["healthCheckCommand"] as? String
                $0.healthCheckPath = project["healthCheckPath"] as? String
                $0.conflictAgentProvider = project["conflictAgentProvider"] as? String
                $0.conflictAgentModel = project["conflictAgentModel"] as? String
                $0.gsdWatcherEnabled = project["gsdWatcherEnabled"] as? Bool
            }
            configureProjectGrids(created, from: project, in: &workspace)
    }

    private static func configureProjectGrids(_ created: ProjectID, from project: [String: Any],
                                             in workspace: inout WorkspaceDocument) {
            if project["autoWorktree"] as? Bool == true { workspace.updateProject(created) { $0.autoWorktree = true } }
            if project["graphifyEnabled"] as? Bool == true { workspace.updateProject(created) { $0.graphifyEnabled = true } }
            if let mode = (project["worktreeMode"] as? String).flatMap(ProjectWorktreeMode.init(rawValue:)) {
                workspace.updateProject(created) { $0.worktreeMode = mode }
            }
            if (project["activeGridId"] as? String).map({ $0 == "default" }) ?? true,
               let mode = (project["layoutMode"] as? String).flatMap(PaneLayoutMode.init(rawValue:)), mode != .auto {
                workspace.updateProject(created) { $0.layoutMode = mode }
            }
            let named: [ProjectGrid] = (project["grids"] as? [[String: Any]] ?? []).compactMap { raw in
                guard let id = raw["id"] as? String, id != "default", let gridName = raw["name"] as? String else { return nil }
                return ProjectGrid(id: ProjectGridID(rawValue: id), name: gridName,
                                   layoutMode: (raw["layoutMode"] as? String).flatMap(PaneLayoutMode.init(rawValue:)).flatMap { $0 ==
                                       .auto ? nil : $0 },
                                   gridLayout: raw["gridLayout"].flatMap(decodeGrid))
            }
            let activeNamed = (project["activeGridId"] as? String).flatMap { id in named.first { $0.id.rawValue == id } }
            if !named.isEmpty {
                let known = Set(named.map(\.id))
                workspace.updateProject(created) { project in
                    project.grids = named
                    for index in project.panes.indices where project.panes[index].gridID.map({ !known.contains($0) }) == true {
                        project.panes[index].gridID = nil
                    }
                    project.activeGridID = activeNamed?.id
                }
            }
            if activeNamed == nil, let raw = project["gridLayout"], let grid = decodeGrid(raw) {
                workspace.updateProject(created) { $0.gridLayout = grid.reconciled($0.panes(in: nil).map(\.id.rawValue)) }
            }
    }


}
