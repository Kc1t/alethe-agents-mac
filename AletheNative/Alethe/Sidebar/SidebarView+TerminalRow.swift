import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

struct SidebarTerminalRow: View {
    let tab: PaneTab
    let project: Project
    let actions: SidebarActions
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var hovering = false

    private var agentTypes: [String] {
        let tabs = actions.workspace.document.paneHolding(tab.id)?.pane.tabs ?? [tab]
        return tabs.reduce(into: [tab.agent]) { agents, entry in
            if !agents.contains(entry.agent) { agents.append(entry.agent) }
        }
    }

    var body: some View {
        let pane = actions.workspace.document.paneHolding(tab.id)?.pane
        let disabled = pane?.isDisabled == true
        let working = pane?.tabs.contains { environment.terminals.activity[$0.id] == .working } == true
        let hidden = metrics.isWebInterface
            ? !(pane.map { actions.workspace.document.webPaneIsVisible($0.id) } ?? false)
            : !actions.workspace.document.workspace.openProjectIDs.contains(project.id)
        let statusTab = pane?.tabs.first { environment.terminals.activity[$0.id] == .working }
            ?? pane?.tabs.first { environment.terminals.unread.contains($0.id) } ?? tab
        Label {
            HStack(spacing: metrics.isWebInterface ? metrics.size(9) : metrics.space(.xs)) {
                Text(verbatim: environment.terminals.displayName(of: tab))
                    .font(metrics.font(size: 12.5))
                    .foregroundStyle(theme[metrics.isWebInterface ? (working ? .fg : disabled ? .textQuaternary
                        : hidden ? .textTertiary : .fg) : (disabled ? .textTertiary : .fgMuted)])
                    .lineLimit(1)
                    .frame(maxWidth: metrics.isWebInterface ? .infinity : nil, alignment: .leading)
                if !metrics.isWebInterface { AgentStatusGlyph(tab: tab.id) }
                if let pane, pane.tabs.count > 1, metrics.isWebInterface || pane.tabs.first?.id == tab.id {
                    if metrics.isWebInterface {
                        Text(verbatim: "\(pane.tabs.count)")
                            .font(metrics.font(size: 11))
                            .foregroundStyle(theme[.textTertiary])
                            .padding(.horizontal, metrics.size(7))
                            .padding(.vertical, metrics.size(4))
                            .fixedSize()
                            .background(theme[.panelHover].opacity(0.6),
                                        in: RoundedRectangle(cornerRadius: metrics.size(5)))
                    } else { AletheCountPill(pane.tabs.count) }
                }
                if !metrics.isWebInterface { Spacer(minLength: metrics.space(.xxs)) }
                if metrics.isWebInterface {
                    SidebarRowEndSlot(active: environment.terminals.activity[statusTab.id] == .working
                        || environment.terminals.unread.contains(statusTab.id), hovering: hovering) {
                        SidebarWebTerminalStatus(tab: statusTab.id)
                    } action: {
                        WebMenu { TabContextMenu(tab: tab, project: project, actions: actions) } label: {
                            Label { Text("sidebar.rowMenu") } icon: { Image(systemName: "ellipsis").webProfileSized(13) }
                        }
                        .menuIndicator(.hidden)
                        .menuStyle(.borderlessButton)
                        .modifier(SidebarMenuAppearance(size: 13))
                        .fixedSize()
                        .help(Text("sidebar.rowMenu"))
                    }
                } else {
                    Menu {
                        TabContextMenu(tab: tab, project: project, actions: actions)
                    } label: {
                        Label { Text("sidebar.rowMenu") } icon: { Image(systemName: "ellipsis").webProfileSized(14) }
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .modifier(SidebarMenuAppearance(size: 13))
                .fixedSize()
                .frame(width: metrics.isWebInterface ? metrics.size(hovering ? 20 : 0) : nil)
                .help(Text("sidebar.rowMenu"))
                .opacity(hovering ? 1 : 0)
                }
                if pane?.isRemoteShared == true { RemoteSharedGlyph() }
                if let branch = tab.worktreeBranch {
                    Image(systemName: "arrow.triangle.branch").webProfileSized(14)
                        .font(metrics.font(.footnote))
                        .foregroundStyle(theme[.textTertiary])
                        .help(Text(verbatim: String(format: String(localized: "sidebar.worktree"), branch)))
                        .accessibilityLabel(Text(verbatim: String(format: String(localized: "sidebar.worktree"), branch)))
                        .accessibilityIdentifier("sidebar.tab.worktree")
                }
            }
        } icon: {
            if metrics.isWebInterface {
                HStack(spacing: metrics.size(2)) {
                    ForEach(agentTypes, id: \.self) { agent in
                        AgentLogo(agent: agent, size: 14)
                            .frame(width: metrics.size(15), height: metrics.size(15))
                    }
                }
                    .saturation(!working && (disabled || hidden) ? 0 : 1)
                    .opacity(!working && (disabled || hidden) ? 0.6 : 1)
            } else {
                Image(systemName: disabled ? "pause.circle"
                      : environment.terminals.hibernated.contains(tab.id) ? "moon.zzz"
                      : tab.agent == "shell" ? "terminal" : "sparkles").webProfileSized(14)
                    .foregroundStyle(theme[disabled ? .statusDisabled : AgentTokens.accent(for: tab.agent)])
                    .saturation(disabled ? 0 : 1)
                    .help(environment.terminals.hibernated.contains(tab.id) ? Text("sidebar.hibernated") : Text(verbatim: ""))
            }
        }
        .modifier(SidebarLabelAppearance(isGroup: false))
        .modifier(SidebarWebRow(kind: .terminal,
            focused: actions.workspace.document.workspace.focusedPaneID == pane?.id, project: project.id))
        .onHover { hovering = $0 }
        .tag(SidebarItem.tab(tab.id))
        .modifier(SidebarWebClick(single: { selectWebPane(individually: false) },
                                  double: { selectWebPane(individually: true) }))
        .modifier(SidebarWebDragSource(payload: pane.map { SidebarDrag.payload($0.id) } ?? "",
                                        name: environment.terminals.displayName(of: tab)))
        .modifier(SidebarWebHelp(text: environment.terminals.displayName(of: tab)))
        .webContextMenu { TabContextMenu(tab: tab, project: project, actions: actions) }
        .accessibilityIdentifier("sidebar.tab.\(tab.agent)")
    }

    private func selectWebPane(individually: Bool) {
        guard let pane = actions.workspace.document.paneHolding(tab.id)?.pane else { return }
        actions.workspace.update {
            if individually { $0.openWebPane(pane.id) } else { $0.focusWebPane(pane.id) }
        }
        environment.terminals.markRead(tab.id)
        environment.showingHome = false
        if environment.inspectedPaneID != nil { environment.inspectedPaneID = pane.id }
        DispatchQueue.main.async { environment.terminals.view(for: tab.id)?.focus() }
    }
}
