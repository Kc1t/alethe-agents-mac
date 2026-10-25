import AletheAgents
import AletheDesign
import AletheGit
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

extension NewTerminalSheet {
    var startsUnrestricted: Bool {
        descriptor?.unrestrictedFlag != nil && (environment.preferences?.document.alwaysStartUnrestricted ?? false)
    }

    var problem: LocalizedStringKey? {
        guard project != nil else { return "newTerminal.problem.project" }
        if let targetPane, workspace.document.pane(targetPane) == nil { return "newSubTab.problem.pane" }
        var isDirectory: ObjCBool = false
        let path = expanded(folder)
        if path.isEmpty || !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            return "editor.problem.folder"
        }
        return nil
    }

    func loadInitial() {
        let last = registry.parse(environment.preferences?.document.lastAgent)
        agent = last.flatMap { agents.contains($0) ? $0 : nil } ?? (agents.contains(.claude) ? .claude : agents.first ?? .shell)
        projectID = initialProject.flatMap { workspace.document.project($0)?.id } ?? workspace.document.projects.first?.id
        folder = project?.folder ?? ""
        gridID = project?.shownGridID
        if let targetPane, let found = workspace.document.pane(targetPane) {
            folder = found.pane.activeTab?.workingDirectory ?? found.project.folder
        }
        unrestricted = startsUnrestricted
        useRouter9 = router9.preferences.defaultForNewAgents
        loadWorktreeDefaults()
    }

    func loadWorktreeDefaults() {
        ownWorktree = project?.usesAutoWorktree ?? false
        worktreeMode = project?.effectiveWorktreeMode == .localCopy ? .localCopy : .gitWorktree
    }

    func discoverModels() async {
        modelsLoading = true
        defer { modelsLoading = false }
        models = []
        let executable = descriptor?.cliCommand.flatMap {
            environment.launchers.resolve($0, override: environment.preferences?.document.cliPaths?[agent.rawValue])
        }
        models = await ModelDiscovery.discover(agent, executable: executable)
    }

    private func expanded(_ path: String) -> String {
        (path.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(filePath: expanded(folder), directoryHint: .isDirectory)
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }

    func create() {
        guard let project else { return }
        worktreeError = nil
        guard descriptor?.isShell == false, ownWorktree else {
            add(in: project, worktree: nil)
            return
        }
        let repo = URL(filePath: expanded(folder)).standardizedFileURL
        let tabID = TabID.make()
        let mode = worktreeMode
        provisioning = true
        Task {
            do {
                let info = try await GitWorktrees().provision(repo: repo, agentId: tabID.rawValue, mode: mode)
                provisioning = false
                add(in: project, worktree: info, tabID: tabID)
            } catch {
                provisioning = false
                worktreeError = Self.describe(error)
            }
        }
    }

    static func describe(_ error: Error) -> String {
        if case let GitError.commandFailed(_, stderr) = error, !stderr.isEmpty { return stderr }
        return String(describing: error)
    }

    func add(in project: Project, worktree: WorktreeInfo?, tabID: TabID = .make()) {
        let path = URL(filePath: expanded(folder)).standardizedFileURL.path
        let projectFolder = URL(filePath: project.folder).standardizedFileURL.path
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var tab = PaneTab(
            id: tabID,
            agent: agent.rawValue,
            workingDirectory: worktree?.path ?? (path == projectFolder ? nil : path),
            unrestricted: descriptor?.unrestrictedFlag != nil && unrestricted,
            extraArguments: ModelDiscovery.arguments([], model: model, for: agent),
            initialPrompt: descriptor?.isShell == false && !text.isEmpty ? text : nil,
            worktreeAgentID: worktree?.agentId,
            worktreeBranch: worktree?.branch
        )
        tab.useRouter9 = routingAvailable && useRouter9 ? true : nil
        if let targetPane {
            workspace.update(undoManager: undoManager, actionName: String(localized: "undo.newSubTab")) {
                $0.addTab(tab, to: targetPane)
            }
        } else {
            let grid = gridID
            let orchestration = orchestrating
            let web = metrics.isWebInterface
            if orchestration, environment.features.isOn(.orchestrator) == false {
                environment.preferences?.update { $0.features.set(.orchestrator, on: true) }
            }
            let actionName = orchestration ? String(localized: "undo.newOrchestration") : String(localized: "undo.newTerminal")
            workspace.update(undoManager: undoManager, actionName: actionName) {
                if grid != $0.project(project.id)?.shownGridID { $0.activateGrid(grid, in: project.id) }
                let planner = $0.addPane(to: project.id, tab: tab)
                if orchestration, let planner {
                    let board = $0.addPane(to: project.id, content: .orchestrator)
                    if web, let board {
                        $0.updateProject(project.id) {
                            $0.groupPanes([planner, board], kind: "orchestration", plannerId: planner)
                        }
                    }
                    $0.workspace.focusedPaneID = planner
                }
            }
            environment.preferences?.update {
                $0.lastTerminalCreation = TerminalCreation(agent: tab.agent, folder: worktree == nil ? tab.workingDirectory : nil,
                                                           unrestricted: tab.unrestricted, extraArguments: tab.extraArguments,
                                                           useRouter9: tab.useRouter9)
            }
        }
        environment.preferences?.update { $0.lastAgent = agent.rawValue }
        if metrics.isWebInterface {
            if !createMore || orchestrating || targetPane != nil { close() }
        } else {
            dismiss()
        }
    }
}
