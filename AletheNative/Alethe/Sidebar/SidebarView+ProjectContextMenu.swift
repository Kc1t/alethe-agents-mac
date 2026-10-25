import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

struct ProjectContextMenu: View {
    @AppStorage(SidebarProjectVisibility.archivedGroupsKey) private var archivedGroups = "[]"

    let project: Project
    let actions: SidebarActions
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.metrics) private var metrics

    @ViewBuilder
    private func projectGroup<C: View>(_ title: LocalizedStringKey, symbol: String,
        @ViewBuilder _ content: @escaping () -> C) -> some View {
        if metrics.isWebInterface { WebSubmenu(title, symbol: symbol, content: content) } else { content() }
    }

    var body: some View {
        let doc = actions.workspace.document
        if metrics.isWebInterface {
            SidebarMenuButton("sidebar.web.openIndividually", symbol: "folder") {
                actions.workspace.update { $0.openWebProject(project.id) }
                environment.showingHome = false
            }
            SidebarMenuButton("sidebar.web.addToCurrent", symbol: "plus") {
                actions.workspace.update { $0.addWebProject(project.id) }
                environment.showingHome = false
            }
            WebMenuDivider()
        }
        if metrics.isWebInterface {
            SidebarMenuButton("terminal.new", symbol: "plus") { environment.editorRequest = .newTerminal(project.id) }
                .accessibilityIdentifier("terminal.new")
        } else { NewTerminalButton(project: project) }
        WebMenuDivider()
        SidebarMenuButton("sidebar.rename", symbol: "pencil") {
            SidebarRenamePrompt.name(initial: project.name, width: metrics.size(280), height: metrics.size(24)) { name in
                actions.workspace.update(undoManager: actions.undoManager, actionName: String(localized: "sidebar.rename")) {
                    $0.updateProject(project.id) { $0.name = name }
                }
            }
        }
        SidebarMenuButton("sidebar.editProject", symbol: "slider.horizontal.3") { environment.editorRequest = .editProject(project.id) }
        projectGroup("sidebar.web.group.openIn", symbol: "arrow.up.forward.app") {
            SidebarMenuButton("sidebar.revealInFinder", symbol: "folder") { actions.revealInFinder(project) }
            SidebarMenuButton("openIn.vscode", symbol: "chevron.left.forwardslash.chevron.right") {
                OpenInActions.vsCode(project.folder, launchers: environment.launchers) }
                .accessibilityIdentifier("openIn.vscode")
            if metrics.isWebInterface, environment.features.isOn(.browser) {
                SidebarMenuButton("menu.addBrowser", symbol: "globe") { environment.editorRequest = .addBrowser(project.id) }
            }
            SidebarMenuButton("openIn.browser", symbol: "globe") { OpenInActions.browser(project) }
                .accessibilityIdentifier("openIn.browser")
        }
        projectGroup("sidebar.web.group.layout", symbol: "rectangle.split.2x2") {
            SidebarMenuButton("sidebar.designLayout", symbol: "rectangle.split.2x2") {
                environment.editorRequest = .layoutDesigner(.project(project.id)) }
            WebSubmenu("sidebar.grids") {
                SidebarMenuButton("projectGrid.main", symbol: "square.grid.2x2") { actions.workspace.update {
                    $0.activateGrid(nil, in: project.id) } }
                ForEach(project.namedGrids) { grid in
                    Button { actions.workspace.update { $0.activateGrid(grid.id, in: project.id) } } label: { Text(verbatim: grid.name) }
                }
                WebMenuDivider()
                SidebarMenuButton("projectGrid.newEllipsis", symbol: "plus") {
                    ProjectGridPrompts.createGrid(in: project.id, workspace: actions.workspace, undoManager: actions.undoManager)
                }
            }
        }
        projectGroup("sidebar.web.group.git", symbol: "arrow.triangle.branch") {
            if environment.hasPluginCommand(GitControlPlugin.openCommandID) {
                SidebarMenuButton("menu.git.control", symbol: "arrow.triangle.branch") {
                    environment.openPluginSheet(GitControlPlugin.sheetID, project: project.id) }
            }
            SidebarMenuButton("menu.merge.center", symbol: "arrow.triangle.merge") { environment.editorRequest = .mergeCenter(project.id) }
            SidebarMenuButton("worktrees.manageEllipsis", symbol: "arrow.triangle.branch") {
                environment.editorRequest = .worktrees(project.id) }
            SidebarMenuButton("menu.merge.branchTesting", symbol: "testtube.2") { environment.editorRequest = .branchTesting(project.id) }
        }
        projectGroup("sidebar.web.group.content", symbol: "books.vertical") {
            SidebarMenuButton("menu.history.conversations", symbol: "clock") { environment.editorRequest = .conversations(project.id) }
            SidebarMenuButton("agentLibrary.openEllipsis", symbol: "books.vertical") {
                environment.editorRequest = .agentLibrary(project.id) }
            if environment.features.isOn(.graphify) {
                SidebarMenuButton("graphify.openInProject", symbol: "point.3.connected.trianglepath.dotted") {
                    environment.open(.graphify, in: project.id, actionName: String(localized: "undo.addContent"))
                }
                .accessibilityIdentifier("graphify.openInProject")
            }
            if environment.features.isOn(.orchestrator) {
                SidebarMenuButton("orchestrator.addToProject", symbol: "rectangle.3.group") {
                    actions.workspace.update(undoManager: actions.undoManager, actionName: String(localized: "undo.addContent")) {
                        $0.addPane(to: project.id, content: .orchestrator)
                    }
                }
                .accessibilityIdentifier("orchestrator.addToProject")
            }
        }
        projectGroup("sidebar.web.group.settings", symbol: "slider.horizontal.3") {
            SidebarMenuButton("projectSettings.exportEllipsis",
                symbol: metrics.isWebInterface ? "arrow.down.to.line" : "square.and.arrow.up") {
                if metrics.isWebInterface {
                    WebProjectTransfer.export(project, group: doc.groups.first { $0.projectIDs.contains(project.id) }?.id)
                } else { ProjectSettingsTransfer.export(project) }
            }
            SidebarMenuButton("projectSettings.importEllipsis",
                symbol: metrics.isWebInterface ? "arrow.up.to.line" : "square.and.arrow.down") {
                if metrics.isWebInterface {
                    WebProjectTransfer.importProject(nextTo: project.id, workspace: actions.workspace, undoManager: actions.undoManager)
                } else {
                    ProjectSettingsTransfer.importSettings(into: project.id, workspace: actions.workspace, undoManager: actions.undoManager)
                }
            }
            WebSubmenu("sidebar.moveToGroup") {
                SidebarMenuButton("sidebar.ungrouped", symbol: "folder") { actions.move(project.id, to: .ungrouped) }
                    .disabled(doc.location(of: project.id) == .ungrouped)
                if !doc.groups.isEmpty { WebMenuDivider() }
                ForEach(doc.groups) { group in
                    Button { actions.move(project.id, to: .group(group.id)) } label: { Text(verbatim: group.name) }
                        .disabled(doc.location(of: project.id) == .group(group.id))
                }
            }
        }
        WebMenuDivider()
        if metrics.isWebInterface {
            SidebarMenuButton("sidebar.web.archiveProject", symbol: "archivebox") {
                actions.workspace.update { $0.updateProject(project.id) { $0.archived = true } }
            }
            let hidden = project.hidden == true
            SidebarMenuButton(hidden ? "sidebar.web.unhideProject" : "sidebar.web.hideProject",
                              symbol: hidden ? "eye" : "eye.slash") {
                actions.workspace.update { $0.updateProject(project.id) { $0.hidden = !hidden } }
            }
        }
        if doc.isProjectDisabled(project.id) {
            SidebarMenuButton("sidebar.enableProject", symbol: metrics.isWebInterface ? "power" : "play") {
                actions.setProjectDisabled(project.id, false) }
        } else {
            SidebarMenuButton("sidebar.disableProject", symbol: metrics.isWebInterface ? "power" : "pause") {
                actions.setProjectDisabled(project.id, true) }
                .disabled(project.panes.isEmpty)
        }
        WebMenuDivider()
        SidebarMenuButton("sidebar.removeProject", symbol: "trash") { actions.remove(project.id) }
    }
}
