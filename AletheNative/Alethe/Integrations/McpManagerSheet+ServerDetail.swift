import AletheDesign
import AletheFoundation
import AletheIntegrations
import AppKit
import SwiftUI

struct McpServerDetail: View {
    let model: McpManagerModel
    let group: McpServerGroup
    let onEdit: (McpServerRecord) -> Void
    let onBackups: (McpServerRecord) -> Void
    let onRemove: ([McpServerRecord]) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    private var primary: McpServerRecord? { group.records.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.isWebInterface ? metrics.size(14) : metrics.space(.xl)) {
                header
                if let owner = group.records.compactMap(\.managedByImport).first {
                    Label { Text(verbatim: format("mcp.importedHint", owner)) } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(metrics.font(.footnote))
                    .foregroundStyle(theme[.statusWaiting])
                }
                agents
                if let primary {
                    section("mcp.detail.env") {
                        McpEnvTable(model: model, record: primary, entries: primary.server.env, header: false)
                    }
                    if let headers = primary.server.transport.headers, !headers.isEmpty {
                        section("mcp.detail.headers") {
                            McpEnvTable(model: model, record: primary, entries: headers, header: true)
                        }
                    }
                }
            }
            .padding(metrics.isWebInterface ? 0 : metrics.space(.xl))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mcp.detail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: metrics.space(.xs)) {
            HStack(spacing: metrics.space(.s)) {
                Text(verbatim: group.name)
                    .font(metrics.isWebInterface ? metrics.font(size: 15, weight: .medium) : metrics.font(.title3))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("mcp.detail.name")
                Spacer()
                Button(role: .destructive) {
                    onRemove(group.records)
                } label: {
                    Text(verbatim: group.records.count > 1
                         ? format("mcp.remove.all", group.records.count)
                         : String(localized: "mcp.remove.action"))
                }
                .disabled(model.busy)
                .accessibilityIdentifier("mcp.detail.remove")
            }
            Text(verbatim: primary?.server.transport.summary ?? "")
                .font(metrics.isWebInterface ? metrics.monoFont(size: 11) : metrics.font(.footnote).monospaced())
                .foregroundStyle(theme[.textSecondary])
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private var agents: some View {
        section("mcp.detail.agents") {
            VStack(alignment: .leading, spacing: metrics.space(.s)) {
                if group.missingAgents.count > 1 {
                    Button {
                        Task { await model.sync(group, to: group.missingAgents) }
                    } label: {
                        Label(format("mcp.sync.all", group.missingAgents.count), systemImage: "square.on.square")
                    }
                    .disabled(model.busy)
                    .accessibilityIdentifier("mcp.detail.syncAll")
                }
                ForEach(McpAgent.allCases, id: \.self) { agent in
                    let records = group.records.filter { $0.agent == agent }
                    if records.isEmpty {
                        absentCard(agent)
                    } else {
                        ForEach(records, id: \.sourceURL) { record in card(record) }
                    }
                }
            }
        }
    }

    private func absentCard(_ agent: McpAgent) -> some View {
        HStack(spacing: metrics.space(.s)) {
            Circle().strokeBorder(theme[agent.colorToken], lineWidth: 1)
                .frame(width: metrics.size(8), height: metrics.size(8))
            Text(verbatim: agent.label).font(metrics.isWebInterface ? metrics.font(size: 12.5) : metrics.font(.body))
            Text(absentReason(agent))
                .font(metrics.font(.caption))
                .foregroundStyle(theme[.textTertiary])
            Spacer(minLength: 0)
            if group.missingAgents.contains(agent) {
                Button {
                    Task { await model.sync(group, to: [agent]) }
                } label: {
                    Label("mcp.sync.here", systemImage: "square.on.square")
                }
                .disabled(model.busy)
                .accessibilityIdentifier("mcp.detail.copy.\(agent.rawValue)")
            }
        }
        .padding(.horizontal, metrics.isWebInterface ? metrics.size(11) : metrics.space(.s))
        .padding(.vertical, metrics.isWebInterface ? metrics.size(9) : metrics.space(.s))
        .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mcp.detail.agent.\(agent.rawValue)")
    }

    private func absentReason(_ agent: McpAgent) -> LocalizedStringKey {
        model.snapshot(agent)?.issue.map(\.title) ?? "mcp.notConfigured"
    }

    private func card(_ record: McpServerRecord) -> some View {
        let agent = record.agent
        return HStack(spacing: metrics.space(.s)) {
            Circle().fill(theme[agent.colorToken]).frame(width: metrics.size(8), height: metrics.size(8))
            Text(verbatim: agent.label)
                .font(metrics.isWebInterface ? metrics.font(size: 12.5, weight: .medium) : metrics.font(.body).weight(.medium))
            if record.sourceKind != .user { McpBadge(title: record.sourceKind.title) }
            if !record.server.enabled {
                McpBadge(title: "mcp.badge.disabled")
                    .accessibilityIdentifier("mcp.detail.disabled.\(agent.rawValue)")
            }
            if let status = model.status(of: record.server.name, on: agent) {
                McpBadge(title: status.title, token: status.token)
                    .accessibilityIdentifier("mcp.detail.status.\(agent.rawValue)")
            } else if let failure = model.healthErrors[agent] {
                McpBadge(title: failure.title, token: .statusStopped)
            }
            Text(verbatim: record.sourceURL.path(percentEncoded: false))
                .font(metrics.font(.caption).monospaced())
                .foregroundStyle(theme[.textSecondary])
                .lineLimit(1)
                .truncationMode(.middle)
                .help(Text(verbatim: record.sourceURL.path(percentEncoded: false)))
                .accessibilityIdentifier("mcp.detail.path.\(agent.rawValue)")
            Spacer(minLength: 0)
            actions(record)
        }
        .padding(.horizontal, metrics.isWebInterface ? metrics.size(11) : metrics.space(.s))
        .padding(.vertical, metrics.isWebInterface ? metrics.size(9) : metrics.space(.s))
        .background(theme[metrics.isWebInterface ? .bgSunken : .surfaceCardDefault],
            in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mcp.detail.agent.\(agent.rawValue)")
    }

    @ViewBuilder private func actions(_ record: McpServerRecord) -> some View {
        let agent = record.agent
        if model.healthAvailable, McpHealthParser.cli(for: agent) != nil {
            Button {
                model.checkHealth(agent)
            } label: {
                Image(systemName: model.checking.contains(agent) ? "hourglass" : "waveform.path.ecg")
            }
            .buttonStyle(.borderless)
            .disabled(model.checking.contains(agent))
            .help(Text("mcp.health.check"))
            .accessibilityLabel(Text("mcp.health.check"))
            .accessibilityIdentifier("mcp.detail.health.\(agent.rawValue)")
        }
        if agent.capability.enabledFlag {
            Button((record.server.enabled ? "mcp.disable" : "mcp.enable") as LocalizedStringKey) {
                Task { await model.toggle(record) }
            }
            .disabled(model.busy)
            .accessibilityIdentifier("mcp.detail.enabled.\(agent.rawValue)")
        }
        iconButton("pencil", "mcp.edit", id: "mcp.detail.edit.\(agent.rawValue)") { onEdit(record) }
        iconButton("clock.arrow.circlepath", "mcp.backups", id: "mcp.detail.backups.\(agent.rawValue)") { onBackups(record) }
        iconButton("folder", "mcp.revealFile", id: "mcp.detail.reveal.\(agent.rawValue)") {
            NSWorkspace.shared.activateFileViewerSelecting([record.sourceURL])
        }
        iconButton("trash", "mcp.remove.action", id: "mcp.detail.remove.\(agent.rawValue)") { onRemove([record]) }
    }

    private func iconButton(_ symbol: String, _ title: LocalizedStringKey, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .disabled(model.busy)
            .help(Text(title))
            .accessibilityLabel(Text(title))
            .accessibilityIdentifier(id)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: metrics.space(.s)) {
            Text(title)
                .font(metrics.font(.footnote).weight(.semibold))
                .foregroundStyle(theme[.textSecondary])
                .textCase(.uppercase)
            content()
        }
    }
}
