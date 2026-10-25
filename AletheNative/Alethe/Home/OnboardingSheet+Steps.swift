import AletheAgents
import AletheDesign
import AletheFoundation
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

struct OnboardingStepTitle: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        if metrics.isWebInterface {
            OnboardingWebIntro(title: title, subtitle: Text(subtitle))
        } else {
            VStack(alignment: .leading, spacing: metrics.space(.xs)) {
                Text(title).font(metrics.font(.title2))
                Text(subtitle)
                    .foregroundStyle(theme[.textSecondary])
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct OnboardingImportStep: View {
    let workspace: WorkspaceModel
    let undoManager: UndoManager?
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var importing = false
    @State private var imported: TauriImport.Report?

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.space(.l)) {
            OnboardingStepTitle(title: "onboarding.import.title", subtitle: "onboarding.import.subtitle")
            if let imported {
                Label {
                    Text(verbatim: format("onboarding.import.done", imported.groups, imported.projects, imported.panes))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").webProfileSized(14).foregroundStyle(theme[.statusActive])
                }
                .accessibilityIdentifier("onboarding.import.summary")
            }
            Button(imported == nil ? LocalizedStringKey("onboarding.import.open") : "onboarding.import.again") { importing = true }
                .accessibilityIdentifier("onboarding.import.open")
            Text("onboarding.import.note")
                .font(metrics.font(.footnote))
                .foregroundStyle(theme[.textTertiary])
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .gitWebSheet(isPresented: $importing, width: 520) {
            TauriImportSheet(workspace: workspace, undoManager: undoManager, onImported: { imported = $0 })
                .environment(environment)
                .environment(\.theme, theme)
                .environment(\.metrics, metrics)
        }
    }
}

struct OnboardingAgentsStep: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.metrics) private var metrics
    @State private var scan = 0

    private var agents: [AgentDescriptor] { AgentRegistry.builtin.descriptors.filter { !$0.isShell } }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.space(.l)) {
            HStack(alignment: .top) {
                OnboardingStepTitle(title: "onboarding.agents.title", subtitle: "onboarding.agents.subtitle")
                Spacer()
                Button("onboarding.agents.rescan") {
                    environment.launchers.invalidate()
                    scan += 1
                }
                .accessibilityIdentifier("onboarding.agents.rescan")
            }
            Form {
                Section {
                    ForEach(agents) { AgentSettingsRow(agent: $0) }
                }
            }
            .formStyle(.grouped)
            .id(scan)
            .accessibilityIdentifier("onboarding.agents")
        }
    }
}

struct OnboardingMcpStep: View {
    let store: McpStore?
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var snapshots: [McpAgentSnapshot]?
    @State private var busy = false
    @State private var copied: Int?
    @State private var notCopied = 0

    private var groups: [McpServerGroup] { McpStore.groups(snapshots ?? []) }
    private var gaps: [McpServerGroup] { groups.filter { !$0.missingAgents.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.space(.l)) {
            OnboardingStepTitle(title: "onboarding.mcp.title", subtitle: "onboarding.mcp.subtitle")
            HStack(spacing: metrics.space(.xl)) {
                stat(groups.count, "onboarding.mcp.stat.servers", theme[.accent])
                stat((snapshots ?? []).filter { $0.isReadable && !$0.servers.isEmpty }.count,
                     "onboarding.mcp.stat.agents", theme[.statusActive])
                stat(gaps.count, "onboarding.mcp.stat.gaps", gaps.isEmpty ? theme[.textTertiary] : theme[.statusWaiting])
            }
            if let snapshots {
                VStack(spacing: 0) {
                    ForEach(snapshots, id: \.agent) { row($0) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("onboarding.mcp.agents")
            } else {
                HStack(spacing: metrics.space(.s)) {
                    ProgressView().controlSize(.small)
                    Text("onboarding.mcp.scanning").foregroundStyle(theme[.textSecondary])
                }
            }
            action
            Spacer(minLength: 0)
        }
        .task { await rescan() }
    }

    private func stat(_ value: Int, _ label: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: metrics.space(.xs)) {
            Circle().fill(color).frame(width: metrics.size(6), height: metrics.size(6))
            Text(verbatim: "\(value)").font(metrics.font(.body).weight(.semibold)).monospacedDigit()
            Text(label).foregroundStyle(theme[.textSecondary])
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ snapshot: McpAgentSnapshot) -> some View {
        let found = snapshot.sources.contains(where: \.exists)
        return HStack(spacing: metrics.space(.m)) {
            Text(verbatim: AgentLabels.name(for: snapshot.agent.rawValue))
            Spacer()
            if !snapshot.servers.isEmpty {
                Text(verbatim: format("onboarding.mcp.serverCount", snapshot.servers.count))
                    .foregroundStyle(theme[.textSecondary])
            }
            Text(!snapshot.isReadable ? LocalizedStringKey("onboarding.mcp.unreadable")
                 : found ? "onboarding.mcp.found" : "onboarding.mcp.missing")
                .font(metrics.font(.footnote))
                .foregroundStyle(!snapshot.isReadable ? theme[.statusWaiting] : found ? theme[.statusActive] : theme[.textTertiary])
        }
        .padding(.vertical, metrics.space(.s))
        .overlay(alignment: .bottom) { Rectangle().fill(theme[.borderSubtle]).frame(height: metrics.size(1)) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.mcp.agent.\(snapshot.agent.rawValue)")
    }

    @ViewBuilder
    private var action: some View {
        if snapshots == nil {
            EmptyView()
        } else if groups.isEmpty {
            note(String(localized: "onboarding.mcp.nothing"))
        } else if !gaps.isEmpty {
            HStack(spacing: metrics.space(.m)) {
                Button {
                    Task { await syncAll() }
                } label: {
                    Text(verbatim: format("onboarding.mcp.syncAll", gaps.count))
                }
                .disabled(busy || store == nil)
                .accessibilityIdentifier("onboarding.mcp.syncAll")
                if busy { ProgressView().controlSize(.small) }
            }
            note(String(localized: "onboarding.mcp.syncHint"))
        } else if let copied, copied > 0 {
            note(format("onboarding.mcp.copied", copied))
        } else {
            note(String(localized: "onboarding.mcp.aligned"))
        }
        if notCopied > 0 {
            Text(verbatim: format("onboarding.mcp.notCopied", notCopied))
                .font(metrics.font(.footnote))
                .foregroundStyle(theme[.statusWaiting])
                .accessibilityIdentifier("onboarding.mcp.notCopied")
        }
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(metrics.font(.footnote))
            .foregroundStyle(theme[.textTertiary])
            .accessibilityIdentifier("onboarding.mcp.note")
    }

    private func rescan() async {
        guard let store else {
            snapshots = []
            return
        }
        snapshots = (try? await store.scan(scope: .global, repository: nil)) ?? []
    }

    private func syncAll() async {
        guard let store else { return }
        busy = true
        defer { busy = false }
        let results = (try? await store.syncAll(gaps, scope: .global, repository: nil)) ?? []
        var written = 0, failed = 0
        for result in results {
            if case .success(let outcomes) = result.result {
                for outcome in outcomes {
                    if case .written = outcome.status {
                        written += 1
                    } else if case .skipped = outcome.status {
                    } else if ({ if case .blocked = outcome.status { return true }; return false }()) ||
                        ({ if case .failed = outcome.status { return true }; return false }()) {
                        failed += 1
                    }
                }
            } else if case .failure = result.result {
                failed += 1
            }
        }
        copied = written
        notCopied = failed
        await rescan()
    }
}
