import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

enum AgentLabels {
    static func name(for agent: String) -> String {
        AgentRegistry.builtin.descriptor(for: AgentKind(rawValue: agent))?.displayName ?? agent
    }
}

struct WorktreeCommitWebHost: View {
    let folder: URL
    let branch: String
    let finish: (WebDialogCenter.Outcome) -> Void
    @State private var message = GitWorktrees.defaultCommitMessage

    var body: some View {
        ConfirmWorktreeCommitWebModal(folder: folder, branch: branch, message: $message) {
            finish(.confirmed(message))
        }
        .environment(\.gitModalClose, { finish(.cancelled) })
    }
}
