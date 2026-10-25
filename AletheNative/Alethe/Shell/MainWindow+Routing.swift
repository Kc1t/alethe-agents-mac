import AletheDesign
import AletheGitControl
import AletheIntegrations
import AletheModel
import SwiftUI

extension MainWindow {
    func modalWidth(_ request: EditorRequest) -> CGFloat {
        if case .worktrees = request {
            620
        } else if case .branchTesting = request {
            560
        } else if case .pluginSheet = request {
            520
        } else if case .mcpManager = request {
            860
        } else if case .mcpIntro = request {
            560
        } else if case .skills = request {
            760
        } else if case .agentLibrary = request {
            660
        } else if case .gistSync = request {
            580
        } else if case .onboarding = request {
            620
        } else if case .addContent = request {
            500
        } else {
            additionalModalWidth(request)
        }
    }

    private func additionalModalWidth(_ request: EditorRequest) -> CGFloat {
        if case .addBrowser = request {
            520
        } else if case .conversations = request {
            680
        } else if case .handoff = request {
            640
        } else if case .sessionCost = request {
            600
        } else if case .diagnostics = request {
            640
        } else if case .remotePairing = request {
            560
        } else if case .previewLink = request {
            760
        } else if case .layoutDesigner = request {
            900
        } else if case .importTauri = request {
            520
        } else if case .gsdSyncActivity = request {
            640
        } else {
            remainingModalWidth(request)
        }
    }

    private func remainingModalWidth(_ request: EditorRequest) -> CGFloat {
        if case .welcome = request {
            480
        } else if case .crashNotice = request {
            560
        } else if case .themePicker = request {
            620
        } else if case .updateAvailable = request {
            480
        } else {
            480
        }
    }

    func projectGroupModalWidth(_ request: EditorRequest) -> CGFloat {
        if case .editProject = request { return 760 }
        return 440
    }

    func isPrimaryWebRequest(_ request: EditorRequest) -> Bool {
        if case .newTerminal = request { return true }
        if case .newSubTab = request { return true }
        if case .newProject = request { return true }
        if case .editProject = request { return true }
        if case .newGroup = request { return true }
        if case .editGroup = request { return true }
        if case .aiUsage = request { return true }
        if case .findJump = request { return true }
        return false
    }

    func isAdditionalWebRequest(_ request: EditorRequest) -> Bool {
        if case .mergeCenter = request { return true }
        if case .worktrees = request { return true }
        if case .branchTesting = request { return true }
        if case .mcpManager = request { return true }
        if case .mcpIntro = request { return true }
        if case .skills = request { return true }
        if case .agentLibrary = request { return true }
        if case .gistSync = request { return true }
        if case .onboarding = request { return true }
        if case .dataManagement = request { return true }
        return isWorkspaceWebRequest(request)
    }

    private func isWorkspaceWebRequest(_ request: EditorRequest) -> Bool {
        if case .addContent = request { return true }
        if case .addBrowser = request { return true }
        if case .conversations = request { return true }
        if case .handoff = request { return true }
        if case .sessionCost = request { return true }
        if case .diagnostics = request { return true }
        if case .remotePairing = request { return true }
        if case .previewLink = request { return true }
        if case .importTauri = request { return true }
        if case .layoutDesigner = request { return true }
        return isUtilityWebRequest(request)
    }

    private func isUtilityWebRequest(_ request: EditorRequest) -> Bool {
        if case .gsdSyncActivity = request { return true }
        if case .welcome = request { return true }
        if case .crashNotice = request { return true }
        if case .themePicker = request { return true }
        if case .updateAvailable = request { return true }
        return false
    }

    func usesGitOverlay(_ request: EditorRequest) -> Bool {
        if case .mergeCenter = request { return true }
        if case .worktrees = request { return true }
        if case .branchTesting = request { return true }
        if case .pluginSheet = request { return true }
        return false
    }

    func usesStandardOverlay(_ request: EditorRequest) -> Bool {
        if case .mcpManager = request { return true }
        if case .mcpIntro = request { return true }
        if case .skills = request { return true }
        if case .agentLibrary = request { return true }
        if case .gistSync = request { return true }
        if case .addContent = request { return true }
        if case .addBrowser = request { return true }
        if case .conversations = request { return true }
        if case .handoff = request { return true }
        if case .sessionCost = request { return true }
        return usesUtilityOverlay(request)
    }

    private func usesUtilityOverlay(_ request: EditorRequest) -> Bool {
        if case .diagnostics = request { return true }
        if case .remotePairing = request { return true }
        if case .previewLink = request { return true }
        if case .importTauri = request { return true }
        if case .layoutDesigner = request { return true }
        if case .gsdSyncActivity = request { return true }
        if case .welcome = request { return true }
        if case .crashNotice = request { return true }
        if case .themePicker = request { return true }
        if case .updateAvailable = request { return true }
        return false
    }

    func usesProjectGroupOverlay(_ request: EditorRequest) -> Bool {
        if case .newProject = request { return true }
        if case .newGroup = request { return true }
        if case .editGroup = request { return true }
        if case .editProject = request { return true }
        return false
    }
}
