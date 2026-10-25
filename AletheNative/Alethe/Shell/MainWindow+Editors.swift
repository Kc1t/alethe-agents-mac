import AletheDesign
import AletheGitControl
import AletheIntegrations
import AletheModel
import SwiftUI

extension MainWindow {
    @ViewBuilder
    func editor(for request: EditorRequest, workspace: WorkspaceModel, closeOverlay: (() -> Void)? = nil) -> some View {
        if case .newProject(let location, let folder) = request {
            ProjectEditor(workspace: workspace, undoManager: undoManager, editing: nil, initialLocation: location,
            initialFolder: folder, closeOverlay: closeOverlay)
        } else if case .editProject(let id) = request {
            ProjectEditor(workspace: workspace, undoManager: undoManager, editing: id, initialLocation: .ungrouped,
                closeOverlay: closeOverlay)
        } else if case .newGroup(let parent) = request {
            GroupEditor(workspace: workspace, undoManager: undoManager, editing: nil, initialParent: parent, closeOverlay: closeOverlay)
        } else if case .editGroup(let id) = request {
            GroupEditor(workspace: workspace, undoManager: undoManager, editing: id, initialParent: nil, closeOverlay: closeOverlay)
        } else if case .newTerminal(let project) = request {
            NewTerminalSheet(workspace: workspace, undoManager: undoManager,
            initialProject: project ?? workspace.document.workspace.selectedProjectID, closeOverlay: closeOverlay)
        } else if case .newSubTab(let pane) = request {
            NewTerminalSheet(workspace: workspace, undoManager: undoManager,
            initialProject: workspace.document.pane(pane)?.project.id, targetPane: pane, closeOverlay: closeOverlay)
        } else if case .addContent(let project) = request {
            AddContentSheet(workspace: workspace, undoManager: undoManager,
            project: project ?? workspace.document.workspace.selectedProjectID)
        } else if case .addBrowser(let project) = request {
            AddBrowserSheet(workspace: workspace, undoManager: undoManager,
            project: project ?? workspace.document.workspace.selectedProjectID)
        } else if case .previewLink(let target) = request {
            LinkPreviewSheet(target: target)
        } else if case .importTauri = request {
            TauriImportSheet(workspace: workspace, undoManager: undoManager)
        } else {
            projectEditor(for: request, workspace: workspace, closeOverlay: closeOverlay)
        }
    }

    @ViewBuilder
    private func projectEditor(for request: EditorRequest, workspace: WorkspaceModel, closeOverlay: (() -> Void)? = nil) -> some View {
        if case .layoutDesigner(let project) = request {
            LayoutDesignerSheet(workspace: workspace, undoManager: undoManager, scope: project)
        } else if case .findJump = request {
            FindJumpSheet(workspace: workspace, undoManager: undoManager)
        } else if case .conversations(let project) = request {
            ConversationsSheet(workspace: workspace, undoManager: undoManager, initialProject: project)
        } else if case .sessionCost(let tab) = request {
            SessionCostSheet(workspace: workspace, tabID: tab)
        } else if case .handoff(let tab) = request {
            HandoffSheet(workspace: workspace, undoManager: undoManager, tabID: tab)
        } else if case .aiUsage = request {
            AIUsageSheet()
        } else if case .pluginSheet(let viewID, let project) = request {
            PluginViewRegistry.sheet(for: viewID, workspace: workspace, undoManager: undoManager,
            projectID: project ?? workspace.document.workspace.selectedProjectID)
        } else if case .mergeCenter(let project, let resume) = request {
            MergeCenterSheet(workspace: workspace, undoManager: undoManager,
            projectID: project ?? workspace.document.workspace.selectedProjectID,
            resumeID: resume)
        } else if case .worktrees(let project) = request {
            WorktreesSheet(workspace: workspace, projectID: project ?? workspace.document.workspace.selectedProjectID)
        } else if case .branchTesting(let project) = request {
            BranchTestingSheet(folder: (project ?? workspace.document.workspace.selectedProjectID)
            .flatMap { workspace.document.project($0) }
            .map { URL(filePath: $0.folder, directoryHint: .isDirectory) })
        } else if case .agentLibrary(let project) = request {
            AgentLibrarySheet(workspace: workspace, projectID: project ?? workspace.document.workspace.selectedProjectID)
        } else {
            utilityEditor(for: request, workspace: workspace, closeOverlay: closeOverlay)
        }
    }

    @ViewBuilder
    private func utilityEditor(for request: EditorRequest, workspace: WorkspaceModel, closeOverlay: (() -> Void)? = nil) -> some View {
        if case .diagnostics = request {
            DiagnosticsSheet()
        } else if case .dataManagement(let action) = request {
            DataManagementSheet(action: action, close: closeOverlay ?? { environment.editorRequest = nil })
        } else if case .crashNotice = request {
            CrashNoticeSheet()
        } else if case .skills = request {
            SkillsSheet(store: environment.skillStore)
        } else if case .gsdSyncActivity(let target) = request {
            GSDSyncActivitySheet(target: target)
        } else if case .onboarding = request {
            OnboardingSheet(workspace: workspace, undoManager: undoManager)
        } else if case .welcome(let welcome) = request {
            WelcomeBackSheet(welcome: welcome)
        } else if case .mcpManager(let route) = request {
            McpManagerSheet(route: route)
        } else if case .mcpIntro = request {
            McpIntroSheet()
        } else if case .remotePairing = request {
            RemotePairingSheet()
        } else if case .gistSync = request {
            GistSyncSheet()
        } else if case .themePicker = request {
            ThemePickerWebModal()
        } else if case .updateAvailable(let release) = request {
            UpdateAvailableWebModal(release: release)
        }
    }
}
