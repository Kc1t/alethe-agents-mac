import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

@MainActor
enum WorktreeActions {
    static func commit(_ agentID: String, project: Project) {
        if WebDialogCenter.shared.themed {
            let repo = URL(filePath: project.folder)
            Task {
                guard let info = try? await GitWorktrees().list(repo: repo).first(where: { $0.agentId == agentID }) else {
                    inform(String(localized: "worktree.failed"), text: "")
                    return
                }
                let outcome = await WebDialogCenter.shared.present(width: 520) { finish in
                    WorktreeCommitWebHost(folder: URL(filePath: info.path), branch: info.branch, finish: finish)
                }
                guard case .confirmed(let message) = outcome else { return }
                do {
                    let committed = try await GitWorktrees().commitPending(repo: repo, agentId: agentID, message: message)
                    if !committed { inform(String(localized: "worktree.nothingToCommit"), text: "") }
                } catch {
                    inform(String(localized: "worktree.failed"), text: NewTerminalSheet.describe(error))
                }
            }
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "worktree.commit.title")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = GitWorktrees.defaultCommitMessage
        field.setAccessibilityIdentifier("worktree.commit.message")
        alert.informativeText = String(localized: "worktree.commit.message")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "worktree.commit.confirm"))
        alert.addButton(withTitle: String(localized: "editor.cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let message = field.stringValue
        let repo = URL(filePath: project.folder)
        Task {
            do {
                let committed = try await GitWorktrees().commitPending(repo: repo, agentId: agentID, message: message)
                if !committed { inform(String(localized: "worktree.nothingToCommit"), text: "") }
            } catch {
                inform(String(localized: "worktree.failed"), text: NewTerminalSheet.describe(error))
            }
        }
    }

    static func remove(_ agentID: String, tab: TabID, project: Project, workspace: WorkspaceModel) {
        if WebDialogCenter.shared.themed {
            Task {
                guard await WebDialogCenter.shared.confirm(
                    String(localized: "worktree.remove.detail"), title: String(localized: "worktree.remove.title"),
                    confirmTitle: String(localized: "worktree.remove"), destructive: true) else { return }
                await removeConfirmed(agentID, tab: tab, project: project, workspace: workspace)
            }
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "worktree.remove.title")
        alert.informativeText = String(localized: "worktree.remove.detail")
        alert.addButton(withTitle: String(localized: "worktree.remove"))
        alert.addButton(withTitle: String(localized: "editor.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await removeConfirmed(agentID, tab: tab, project: project, workspace: workspace) }
    }

    private static func removeConfirmed(_ agentID: String, tab: TabID, project: Project, workspace: WorkspaceModel) async {
        let repo = URL(filePath: project.folder)
        do {
            try await GitWorktrees().remove(repo: repo, agentId: agentID, force: true)
            workspace.update {
                $0.updateTab(tab) {
                    $0.worktreeAgentID = nil
                    $0.worktreeBranch = nil
                    $0.workingDirectory = nil
                }
            }
        } catch {
            inform(String(localized: "worktree.failed"), text: NewTerminalSheet.describe(error))
        }
    }

    private static func inform(_ title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
