import AletheAgents
import AletheDesign
import AletheModel
import SwiftUI

struct AgentStatusGlyph: View {
    let tab: TabID
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        let activity = environment.terminals.activity[tab]
        let unread = environment.terminals.unread.contains(tab)
        Group {
            if case .working = activity {
                AletheActivitySpinner()
                    .help(Text("agentStatus.working"))
                    .accessibilityLabel(Text("agentStatus.working"))
            } else if case .needsInput = activity {
                Image(systemName: "questionmark.bubble.fill").webProfileSized(14)
                    .font(metrics.font(.caption))
                    .foregroundStyle(theme[.statusWaiting])
                    .help(Text("agentStatus.needsInput"))
                    .accessibilityLabel(Text("agentStatus.needsInput"))
            } else if case .done = activity, unread {
                Text(verbatim: "✓")
                    .font(metrics.monoFont(size: 11, weight: .bold))
                    .foregroundStyle(theme[.statusWorking])
                    .opacity(0.55)
                    .help(Text("agentStatus.done"))
                    .accessibilityLabel(Text("agentStatus.done"))
            } else {
                EmptyView()
            }
        }
        .accessibilityIdentifier("agentStatus.\(tab.rawValue)")
    }
}
