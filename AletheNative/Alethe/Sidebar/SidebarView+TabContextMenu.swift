import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

struct TabContextMenu: View {
    let tab: PaneTab
    let project: Project
    let actions: SidebarActions
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.metrics) private var metrics

    var body: some View {
        if metrics.isWebInterface { webMenu } else { nativeMenu }
    }

    @ViewBuilder private var webMenu: some View {
        if let pane = actions.workspace.document.paneHolding(tab.id)?.pane {
            if !project.namedGrids.isEmpty {
                WebSubmenu("pane.moveToGrid") {
                    Button("projectGrid.main") { move(pane.id, to: nil) }
                    ForEach(project.namedGrids) { grid in
                        Button { move(pane.id, to: grid.id) } label: { Text(verbatim: grid.name) }
                    }
                }
            }
            SidebarMenuButton("terminalInspector.open", symbol: "info.circle") {
                environment.inspectedPaneID = pane.id
            }
            SidebarMenuButton("sidebar.web.revealTerminal", symbol: "rectangle.topthird.inset.filled") {
                environment.inspectedPaneID = pane.id
                reveal(pane.id)
            }
            if environment.terminals.states[tab.id] != nil && !pane.isDisabled {
                SidebarMenuButton("pane.web.restart", symbol: "power") {
                    environment.terminals.restart(tab, in: project, environment: environment)
                }
            }
            SidebarMenuButton("pane.web.openInExplorer", symbol: "folder") {
                OpenInActions.revealInFinder(tab.workingDirectory ?? project.folder)
            }
            SidebarMenuButton("pane.web.openInVscode", symbol: "folder") {
                OpenInActions.vsCode(tab.workingDirectory ?? project.folder, launchers: environment.launchers)
            }
            SidebarMenuButton("pane.web.focusMode", symbol: "rectangle.topthird.inset.filled") {
                reveal(pane.id)
                environment.focusModePaneID = pane.id
            }
            if pane.tabs.count <= 1 {
                Button(pane.isLaneVisible ? LocalizedStringKey("pane.web.hideTabsLane") : "pane.web.showTabsLane") {
                    actions.setLaneVisible(!pane.isLaneVisible, for: pane.id)
                }
            }
            WebMenuDivider()
            Button("sidebar.web.openIndividually") {
                actions.workspace.update { $0.openWebPane(pane.id) }
                environment.showingHome = false
            }
            Button("pane.web.addToCurrent") {
                actions.workspace.update { $0.addWebProject(project.id); $0.focusWebPane(pane.id) }
                environment.showingHome = false
            }
            WebMenuDivider()
            SidebarMenuButton("sidebar.rename", symbol: "pencil") {
                SidebarRenamePrompt.name(initial: environment.terminals.displayName(of: tab),
                    width: metrics.size(280), height: metrics.size(24)) { name in
                    actions.workspace.update { $0.updateTab(tab.id) { $0.title = name.trimmingCharacters(in: .whitespacesAndNewlines) } }
                }
            }
            SidebarMenuButton(pane.isRemoteShared ? "pane.web.hideFromRemote" : "pane.web.shareWithRemote", symbol: "iphone") {
                environment.remoteControl.setShared(pane.id, !pane.isRemoteShared)
            }
            .accessibilityIdentifier("remote.share")
            SidebarMenuButton(pane.isDisabled ? "pane.web.reactivate" : "pane.web.disable", symbol: "power") {
                actions.setTabDisabled(tab.id, !pane.isDisabled)
            }
            SidebarMenuButton("pane.web.killTerminal", symbol: "power") {
                environment.terminals.view(for: tab.id)?.terminate()
            }
            WebMenuDivider()
            SidebarMenuButton("pane.web.deleteTerminal", symbol: "trash", role: .destructive) {
                Task {
                    guard await WebDialogCenter.shared.confirm(
                        format("pane.web.confirmDeleteTerminal", environment.terminals.displayName(of: tab)),
                        confirmTitle: String(localized: "pane.web.deleteTerminal"), destructive: true) else { return }
                    for entry in pane.tabs { actions.closeTab(entry.id) }
                }
            }
        }
    }

    private func reveal(_ pane: PaneID) {
        actions.workspace.update { $0.focusWebPane(pane) }
        environment.showingHome = false
        environment.terminals.markRead(tab.id)
        DispatchQueue.main.async { environment.terminals.view(for: tab.id)?.focus() }
    }

    @ViewBuilder private var nativeMenu: some View {
        if metrics.isWebInterface, let pane = actions.workspace.document.paneHolding(tab.id)?.pane {
            SidebarMenuButton("sidebar.web.revealTerminal", symbol: "rectangle.topthird.inset.filled") {
                actions.workspace.update { $0.focusWebPane(pane.id) }
                environment.showingHome = false
                environment.terminals.markRead(tab.id)
                DispatchQueue.main.async { environment.terminals.view(for: tab.id)?.focus() }
            }
            SidebarMenuButton("sidebar.web.openIndividually", symbol: "folder") {
                actions.workspace.update { $0.openWebPane(pane.id) }
                environment.showingHome = false
            }
            WebMenuDivider()
        }
        SidebarMenuButton("sidebar.rename", symbol: "pencil") {
            SidebarRenamePrompt.name(initial: tab.title ?? "", width: metrics.size(280), height: metrics.size(24)) { name in
                actions.workspace.update(undoManager: actions.undoManager, actionName: String(localized: "sidebar.rename")) {
                    $0.updateTab(tab.id) { $0.title = name }
                }
            }
        }
        SidebarMenuButton("sidebar.killTerminal", symbol: "stop") { environment.terminals.view(for: tab.id)?.terminate() }
            .disabled(environment.terminals.view(for: tab.id) == nil)
        SidebarMenuButton("terminal.restart", symbol: "arrow.clockwise") { environment.terminals.restart(tab,
            in: project, environment: environment)
        }
        SidebarMenuButton("openIn.vscode", symbol: "chevron.left.forwardslash.chevron.right") {
            OpenInActions.vsCode(tab.workingDirectory ?? project.folder, launchers: environment.launchers)
        }
        SidebarMenuButton("sidebar.revealInFinder", symbol: "folder") {
            OpenInActions.revealInFinder(tab.workingDirectory ?? project.folder)
        }
        if let pane = actions.workspace.document.paneHolding(tab.id)?.pane {
            SidebarMenuButton(environment.focusModePaneID == pane.id ? LocalizedStringKey("focusMode.exit") : "focusMode.enter",
                symbol: "arrow.up.left.and.arrow.down.right") {
                if environment.focusModePaneID == pane.id {
                    environment.focusModePaneID = nil
                } else {
                    if metrics.isWebInterface {
                        actions.workspace.update { $0.focusWebPane(pane.id) }
                        environment.showingHome = false
                    } else { actions.select(.tab(tab.id)) }
                    environment.focusModePaneID = pane.id
                }
            }
            if !project.namedGrids.isEmpty {
                WebSubmenu("pane.moveToGrid") {
                    SidebarMenuButton("projectGrid.main", symbol: "square.grid.2x2") { move(pane.id, to: nil) }
                        .disabled(pane.gridID == nil)
                    ForEach(project.namedGrids) { grid in
                        Button { move(pane.id, to: grid.id) } label: { Text(verbatim: grid.name) }
                            .disabled(pane.gridID == grid.id)
                    }
                }
            }
            SidebarMenuButton(pane.isDisabled ? LocalizedStringKey("pane.enable") : "pane.disable", symbol: "power") {
                actions.setTabDisabled(tab.id, !pane.isDisabled)
            }
            WebMenuDivider()
            SidebarMenuButton("subtabs.newEllipsis", symbol: "plus") { environment.editorRequest = .newSubTab(pane.id) }
            SidebarMenuButton(pane.isLaneVisible ? LocalizedStringKey("subtabs.hideLane") : "subtabs.showLane",
                symbol: "rectangle.split.1x2") {
                actions.setLaneVisible(!pane.isLaneVisible, for: pane.id)
            }
            .disabled(pane.tabs.count > 1)
            if pane.content.isTerminal {
                WebMenuDivider()
                RemoteShareToggle(pane: pane)
            }
        }
        if let agentID = tab.worktreeAgentID {
            WebMenuDivider()
            SidebarMenuButton("worktree.commitEllipsis", symbol: "checkmark") { WorktreeActions.commit(agentID, project: project) }
            SidebarMenuButton("worktree.remove", symbol: "trash") {
                WorktreeActions.remove(agentID, tab: tab.id, project: project, workspace: actions.workspace)
            }
        }
        WebMenuDivider()
        SidebarMenuButton("terminal.close", symbol: "xmark") { actions.closeTab(tab.id) }
    }

    private func move(_ pane: PaneID, to grid: ProjectGridID?) {
        actions.workspace.update(undoManager: actions.undoManager, actionName: String(localized: "undo.move")) {
            $0.movePane(pane, toGrid: grid)
        }
    }
}
