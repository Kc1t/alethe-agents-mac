import AletheAgents
import AletheDesign
import AletheModel
import AppKit
import SwiftUI

struct QuickProjectStyle: ViewModifier {
    @Environment(\.metrics) private var metrics
    func body(content: Content) -> some View {
        if metrics.isWebInterface { content.buttonStyle(HomeQuickFieldStyle()) }
        else { content }
    }
}

struct HomeWebNotifications: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.size(12)) {
            HStack {
                HomeSectionHeader(title: "notifications.title", count: environment.notifier.log.entries.isEmpty ? nil :
                    environment.notifier.log.entries.count)
                Spacer()
                if !environment.notifier.log.entries.isEmpty {
                    Button("notifications.clear") { environment.notifier.clear() }.buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                if environment.notifier.log.entries.isEmpty {
                    VStack(spacing: metrics.size(10)) {
                        Image(systemName: "checkmark.circle").webProfileSized(18).font(metrics.font(size: 18))
                            .foregroundStyle(theme[.statusWorking])
                            .frame(width: metrics.size(56), height: metrics.size(56))
                            .background(theme[.statusWorking].opacity(0.14), in: RoundedRectangle(cornerRadius: metrics.size(18)))
                        Text("home.web.caughtUp").font(metrics.font(size: 14, weight: .semibold))
                        Text("home.notifications.emptyDetail").font(metrics.font(size: 12))
                            .foregroundStyle(theme[.textTertiary])
                    }
                    .padding(metrics.size(20)).frame(maxWidth: .infinity, minHeight: metrics.size(148))
                }
                ForEach(environment.notifier.log.entries.prefix(5)) { entry in
                    Button {
                        if let tab = entry.tab { environment.notifier.open(tab) }
                    } label: {
                        HStack(alignment: .top, spacing: metrics.size(11)) {
                            Group {
                                if let agent = entry.agent {
                                    AgentLogo(agent: agent, size: 14)
                                } else {
                                    Image(systemName: "bell").webProfileSized(14).font(metrics.font(size: 14))
                                }
                            }
                                .foregroundStyle(theme[entry.agent.map { AgentTokens.accent(for: $0) } ?? .textSecondary])
                                .frame(width: metrics.size(26), height: metrics.size(26))
                            VStack(alignment: .leading, spacing: metrics.size(2)) {
                                Text(verbatim: entry.title).font(metrics.font(size: 12, weight: .medium)).lineLimit(1)
                                Text(verbatim: entry.body).font(metrics.font(size: 11)).foregroundStyle(theme[.textTertiary]).lineLimit(2)
                            }
                            Spacer()
                            Text(entry.createdAt, format: .relative(presentation: .named)).font(metrics.monoFont(size: 10))
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, metrics.size(14)).padding(.vertical, metrics.size(12))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("notifications.entry")
                }
            }
            .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.lg)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.lg))
                .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("notifications.list")
    }
}

struct HomeWebHelp: ViewModifier {
    let text: String
    @Environment(\.metrics) private var metrics
    func body(content: Content) -> some View {
        if metrics.isWebInterface { content.help(Text(verbatim: text)) }
        else { content }
    }
}

struct HomeWebTerminalBarClip: ViewModifier {
    @Environment(\.metrics) private var metrics
    func body(content: Content) -> some View {
        if metrics.isWebInterface {
            content.clipShape(UnevenRoundedRectangle(
                topLeadingRadius: metrics.radius(.lg), topTrailingRadius: metrics.radius(.lg)))
        } else { content }
    }
}
