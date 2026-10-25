import AletheDesign
import AletheFoundation
import AletheIntegrations
import AppKit
import SwiftUI

struct McpIntroSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modalsM2Close) private var closeOverlay
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var snapshots: [McpAgentSnapshot]?

    var body: some View {
        Group {
            if metrics.isWebInterface { webBody } else { nativeBody }
        }
        .task {
            guard let store = environment.mcp?.store else { return }
            snapshots = (try? await store.scan(scope: .global, repository: nil)) ?? []
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mcp.intro")
    }

    private var webGroups: [McpServerGroup] { McpStore.groups(snapshots ?? []) }
    private var webGaps: [McpServerGroup] { webGroups.filter { !$0.missingAgents.isEmpty } }

    private var webBody: some View {
        ModalsM2WebModal(title: Text("mcp.intro.title"), close: { markSeen(); closeWeb() }, width: 640) {
            VStack(alignment: .leading, spacing: metrics.size(12)) {
                VStack(alignment: .leading, spacing: metrics.size(1)) {
                    Text("modalsM2.mcp.onboardingTitle").font(metrics.font(size: 19, weight: .medium)).tracking(metrics.size(-0.38))
                    Text("modalsM2.mcp.onboardingSubtitle").font(metrics.font(size: 13)).foregroundStyle(theme[.fgMuted])
                }
                HStack(spacing: metrics.size(7)) {
                    webStat(webGroups.count, title: "modalsM2.mcp.servers", token: .accent)
                    webStat((snapshots ?? []).filter { !$0.servers.isEmpty && $0.issue == nil }.count,
                            title: "modalsM2.mcp.agents", token: .statusWorking)
                    webStat(webGaps.count, title: "modalsM2.mcp.gaps", token: webGaps.isEmpty ? .fgFaint : .statusWaiting)
                }
                VStack(spacing: 0) {
                    if let snapshots {
                        ForEach(snapshots, id: \.agent) { snapshot in
                            HStack(spacing: metrics.size(12)) {
                                Text(verbatim: snapshot.agent.label).font(metrics.font(size: 13, weight: .medium))
                                Spacer(minLength: 0)
                                if !snapshot.servers.isEmpty {
                                    Text(verbatim: format("mcp.stats.servers", snapshot.servers.count))
                                        .font(metrics.font(size: 11.5)).foregroundStyle(theme[.fgFaint])
                                }
                                let found = snapshot.sources.contains(where: \.exists)
                                HStack(spacing: metrics.size(6)) {
                                    Circle().fill(theme[snapshot.issue != nil ? .statusWaiting : found ? .statusWorking : .fgFaint])
                                        .frame(width: metrics.size(5), height: metrics.size(5))
                                    Text(
                                        snapshot.issue != nil ? "modalsM2.mcp.unreadable"
                                            : found ? "modalsM2.mcp.found" : "mcp.intro.noConfig"
                                    )
                                }
                                .font(metrics.font(size: 11.5))
                                .foregroundStyle(theme[snapshot.issue != nil ? .statusWaiting : found ? .statusWorking : .fgFaint])
                                .padding(.horizontal, metrics.size(9)).padding(.vertical, metrics.size(3))
                                .overlay(Capsule().strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                            }
                            .padding(.horizontal, metrics.size(12)).padding(.vertical, metrics.size(10))
                            .overlay(alignment: .bottom) { Rectangle().fill(theme[.border]).frame(height: metrics.size(1)) }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("mcp.intro.agent.\(snapshot.agent.rawValue)")
                        }
                    } else {
                        Text("modalsM2.mcp.scanning").font(metrics.font(size: 12)).foregroundStyle(theme[.fgFaint])
                            .frame(maxWidth: .infinity).padding(.vertical, metrics.size(18))
                    }
                }
                .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
                .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                if snapshots != nil {
                    Text(webGroups.isEmpty ? "modalsM2.mcp.nothing" : "modalsM2.mcp.syncHint")
                        .font(metrics.font(size: 12.5)).foregroundStyle(theme[.fgMuted])
                }
            }
        } footer: {
            Spacer()
            Button("mcp.intro.later") { markSeen(); closeWeb() }
                .accessibilityIdentifier("mcp.intro.later")
            Button("mcp.intro.open") { markSeen(); environment.editorRequest = .mcpManager(McpManagerRoute()) }
                .buttonStyle(AletheButtonStyle(.primary)).keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("mcp.intro.open")
        }
    }

    private func webStat(_ value: Int, title: LocalizedStringKey, token: ThemeToken) -> some View {
        HStack(spacing: metrics.size(7)) {
            Circle().fill(theme[token]).frame(width: metrics.size(5), height: metrics.size(5))
            Text(verbatim: "\(value)").font(metrics.font(size: 12, weight: .medium)).foregroundStyle(theme[.fg])
            Text(title).font(metrics.font(size: 12)).foregroundStyle(theme[.fgMuted])
        }
        .padding(.leading, metrics.size(9)).padding(.trailing, metrics.size(11)).padding(.vertical, metrics.size(4))
        .background(theme[.bgSunken], in: Capsule())
        .overlay(Capsule().strokeBorder(theme[.border], lineWidth: metrics.size(1)))
    }

    private func closeWeb() { if let closeOverlay { closeOverlay() } else { dismiss() } }

    private var nativeBody: some View {
        VStack(alignment: .leading, spacing: metrics.space(.l)) {
            Text("mcp.intro.title").font(metrics.font(.title2))
            Text("mcp.intro.detail")
                .font(metrics.font(.body))
                .foregroundStyle(theme[.textSecondary])
                .fixedSize(horizontal: false, vertical: true)
            if let snapshots {
                VStack(alignment: .leading, spacing: metrics.space(.xs)) {
                    ForEach(snapshots, id: \.agent) { snapshot in
                        HStack(spacing: metrics.space(.s)) {
                            Circle().fill(theme[snapshot.agent.colorToken]).frame(width: metrics.size(8), height: metrics.size(8))
                            Text(verbatim: snapshot.agent.label).font(metrics.font(.body).weight(.medium))
                            Spacer()
                            if snapshot.sources.contains(where: \.exists) {
                                Text(verbatim: format("mcp.stats.servers", snapshot.servers.count))
                                    .foregroundStyle(theme[.textSecondary])
                            } else {
                                Text("mcp.intro.noConfig").foregroundStyle(theme[.textTertiary])
                            }
                        }
                        .font(metrics.font(.footnote))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("mcp.intro.agent.\(snapshot.agent.rawValue)")
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            HStack {
                Spacer()
                Button("mcp.intro.later") {
                    markSeen()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("mcp.intro.later")
                Button("mcp.intro.open") {
                    markSeen()
                    environment.editorRequest = .mcpManager(McpManagerRoute())
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("mcp.intro.open")
            }
        }
        .padding(metrics.space(.xxl))
        .frame(width: metrics.size(520))
    }

    private func markSeen() {
        environment.preferences?.update { $0.mcpOnboardingSeen = true }
    }
}
