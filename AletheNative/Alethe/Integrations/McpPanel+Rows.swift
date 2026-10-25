import AletheDesign
import AletheIntegrations
import AletheModel
import AlethePluginKit
import SwiftUI

extension McpPanelContent {
    func serverRow(_ group: McpServerGroup) -> some View {
        Button {
            environment.editorRequest = .mcpManager(McpManagerRoute(server: group.name))
        } label: {
            VStack(alignment: .leading, spacing: metrics.isWebInterface ? metrics.size(5) : metrics.space(.xxs)) {
                HStack(spacing: metrics.isWebInterface ? metrics.size(8) : metrics.space(.xs)) {
                    if !metrics.isWebInterface, let status = model.status(of: group) {
                        McpHealthDot(status: status)
                    }
                    Text(verbatim: group.name)
                        .frame(maxWidth: metrics.isWebInterface ? .infinity : nil, alignment: .leading)
                        .font(metrics.isWebInterface ? metrics.font(size: 12.5, weight: .medium) : metrics.font(.body).weight(.medium))
                        .lineLimit(1)
                        .truncationMode(metrics.isWebInterface ? .tail : .middle)
                    if group.hasDisabled { McpBadge(title: "mcp.badge.disabled") }
                    if group.records.contains(where: { $0.managedByImport != nil }) {
                        McpBadge(title: "mcp.badge.imported", token: .statusWaiting)
                    }
                    Spacer(minLength: 0)
                    McpAgentDots(present: group.agents, missing: group.missingAgents)
                }
                Text(verbatim: group.records.first?.server.transport.summary ?? "")
                    .font(metrics.isWebInterface ? metrics.monoFont(size: 10.5, weight: .regular) : metrics.font(.caption).monospaced())
                    .foregroundStyle(theme[metrics.isWebInterface ? .fgFaint : .textSecondary])
                    .lineLimit(1)
                    .truncationMode(metrics.isWebInterface ? .tail : .middle)
            }
            .padding(metrics.isWebInterface ? metrics.size(8) : metrics.space(.s))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme[.surfaceCardDefault].opacity(metrics.isWebInterface ? 0 : 1), in: RoundedRectangle(cornerRadius: metrics.radius(.md))
            )
            .modifier(McpWebRowBackground())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: presence(group)))
        .accessibilityIdentifier("mcp.panel.row.\(group.name)")
    }

    func presence(_ group: McpServerGroup) -> String {
        var text = format("mcp.presentOn", McpManagerModel.labels(group.agents))
        if !group.missingAgents.isEmpty { text += " · " + format("mcp.missingOn", McpManagerModel.labels(group.missingAgents)) }
        return text
    }

    func skillRow(_ group: SkillGroup) -> some View {
        Button {
            environment.editorRequest = .mcpManager(McpManagerRoute(tab: .skills))
        } label: {
            VStack(alignment: .leading, spacing: metrics.isWebInterface ? metrics.size(5) : metrics.space(.xxs)) {
                HStack(spacing: metrics.isWebInterface ? metrics.size(8) : metrics.space(.xs)) {
                    Text(verbatim: group.name)
                        .font(metrics.isWebInterface ? metrics.font(size: 12.5, weight: .medium) : metrics.font(.body).weight(.medium))
                        .lineLimit(1)
                    if group.bundled {
                        Group {
                            if metrics.isWebInterface {
                                Image(systemName: "lock").resizable().scaledToFit()
                                    .frame(width: metrics.size(11), height: metrics.size(11))
                            } else { Image(systemName: "lock.fill") }
                        }
                        .foregroundStyle(theme[.textTertiary])
                        .accessibilityLabel(Text("skills.badge.bundled"))
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: metrics.isWebInterface ? metrics.size(3) : metrics.space(.xxs)) {
                        ForEach(group.agents, id: \.self) { agent in
                            Group {
                                if metrics.isWebInterface {
                                    AgentLogo(agent: agent.rawValue, size: 13)
                                } else {
                                    Circle().fill(theme[agent.colorToken]).frame(width: metrics.size(7), height: metrics.size(7))
                                }
                            }
                        }
                    }
                }
                Text(verbatim: group.description.isEmpty ? group.agents.map(\.label).joined(separator: ", ") : group.description)
                    .font(metrics.isWebInterface ? metrics.monoFont(size: 10.5, weight: .regular) : metrics.font(.caption))
                    .foregroundStyle(theme[metrics.isWebInterface ? .fgFaint : .textSecondary])
                    .lineLimit(metrics.isWebInterface ? 1 : 2)
            }
            .padding(metrics.isWebInterface ? metrics.size(8) : metrics.space(.s))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme[.surfaceCardDefault].opacity(metrics.isWebInterface ? 0 : 1), in: RoundedRectangle(cornerRadius: metrics.radius(.md))
            )
            .modifier(McpWebRowBackground())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mcp.panel.skill.\(group.name)")
    }

    var addButton: some View {
        Group {
            if metrics.isWebInterface {
                Button {
                    environment.editorRequest = .mcpManager(
                        section == .servers ? McpManagerRoute(add: true) : McpManagerRoute(tab: .skills))
                } label: {
                    HStack(spacing: metrics.size(6)) {
                        Image(systemName: "plus").resizable().scaledToFit()
                            .frame(width: metrics.size(13), height: metrics.size(13))
                        Text((section == .servers ? "rightSidebar.mcp.addMore" : "mcp.manageSkills") as LocalizedStringKey)
                    }
                }.buttonStyle(AletheSidebarFilterStyle(kind: .add))
                    .accessibilityIdentifier("mcp.panel.add")
            } else {
                nativeAddButton
            }
        }
    }

    var nativeAddButton: some View {
        Button {
            environment.editorRequest = .mcpManager(section == .servers ? McpManagerRoute(add: true) : McpManagerRoute(tab: .skills))
        } label: {
            Label(
                (section == .servers ? "mcp.addServer" : "mcp.manageSkills") as LocalizedStringKey,
                systemImage: section == .servers ? "plus" : "wand.and.stars"
            )
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(section == .servers && model.writableAgents.isEmpty)
        .accessibilityIdentifier("mcp.panel.add")
    }

    @ViewBuilder var diagnostics: some View {
        if metrics.isWebInterface {
            VStack(alignment: .leading, spacing: metrics.size(6)) {
                Text("mcp.diag.title").font(metrics.font(size: 10.5))
                    .tracking(metrics.size(0.42)).textCase(.uppercase).foregroundStyle(theme[.fgFaint])
                ForEach(model.issues, id: \.agent) { item in
                    HStack(spacing: metrics.size(7)) {
                        Text(verbatim: item.agent.label).foregroundStyle(theme[.fg])
                            .frame(minWidth: metrics.size(76), alignment: .leading).fixedSize(horizontal: true, vertical: false)
                        Text(item.issue.title).foregroundStyle(theme[.fgFaint]).lineLimit(1)
                    }.font(metrics.font(size: 11.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, metrics.size(8)).padding(.horizontal, metrics.size(12)).padding(.bottom, metrics.size(10))
            .overlay(alignment: .top) { Rectangle().fill(theme[.borderSubtle]).frame(height: metrics.size(1)) }
            .accessibilityElement(children: .combine).accessibilityIdentifier("mcp.panel.diagnostics")
        } else { nativeDiagnostics }
    }

    var nativeDiagnostics: some View {
        VStack(alignment: .leading, spacing: metrics.space(.xxs)) {
            Text("mcp.diag.title")
                .font(metrics.font(.caption).weight(.semibold))
                .foregroundStyle(theme[.textSecondary])
                .textCase(.uppercase)
            ForEach(model.issues, id: \.agent) { item in
                HStack(alignment: .firstTextBaseline, spacing: metrics.space(.xs)) {
                    Text(verbatim: item.agent.label)
                        .font(metrics.font(.caption).weight(.medium))
                    Text(item.issue.title)
                        .font(metrics.font(.caption))
                        .foregroundStyle(theme[.textSecondary])
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mcp.panel.diagnostics")
    }

    func banner(_ text: String, symbol: String, token: ThemeToken, id: String) -> some View {
        Label {
            Text(verbatim: text).textSelection(.enabled)
        } icon: {
            Image(systemName: symbol)
        }
        .font(metrics.font(.footnote))
        .foregroundStyle(theme[token])
        .accessibilityIdentifier(id)
    }

    func loadSkills() async {
        let snapshots = (try? await skillStore.scan()) ?? []
        skills = SkillGroup.group(snapshots)
    }
}
