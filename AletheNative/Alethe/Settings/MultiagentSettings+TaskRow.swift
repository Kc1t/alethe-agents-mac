import AletheDesign
import AletheFoundation
import AletheGit
import AletheIntegrations
import AletheModel
import AletheOrchestrator
import SwiftUI

struct TaskRow: View {
    let task: SchedulerTask
    let index: Int
    let titles: [String: String]
    let onCancel: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(alignment: .top, spacing: metrics.space(.m)) {
            VStack(alignment: .leading, spacing: metrics.space(.xxs)) {
                HStack(spacing: metrics.space(.s)) {
                    Text(verbatim: task.title)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(task.status.label)
                        .font(metrics.isWebInterface ? metrics.font(size: 10).weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(task.status.color(theme))
                        .id(task.status)
                        .accessibilityIdentifier("multiagent.task.\(index).status")
                }
                if !task.dependencies.isEmpty {
                    Text(verbatim: format("settings.multiagent.dependsOn",
                                          task.dependencies.map { titles[$0] ?? $0 }.formatted(.list(type: .and))))
                        .font(metrics.isWebInterface ? metrics.font(size: 10) : .caption)
                        .foregroundStyle(theme[.textSecondary])
                }
                if let agent = task.assignedAgentID {
                    Text(verbatim: format("settings.multiagent.assignedTo", agent))
                        .font(metrics.isWebInterface ? metrics.monoFont(size: 10, weight: .regular) : .caption.monospaced())
                        .foregroundStyle(theme[.textTertiary])
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            if task.status == .running {
                Button("settings.multiagent.cancel", action: onCancel)
                    .accessibilityIdentifier("multiagent.task.\(index).cancel")
                .settingsRowSurface(.standalone)
            }
        }
        .accessibilityIdentifier("multiagent.task.\(index)")
    }
}
