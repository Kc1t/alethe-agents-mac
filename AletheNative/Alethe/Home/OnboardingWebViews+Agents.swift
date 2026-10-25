import AletheAgents
import AletheDesign
import AletheFoundation
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

struct OnboardingWebAgentsStep: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @State private var scan = 0

    private var agents: [AgentDescriptor] { AgentRegistry.builtin.descriptors.filter { !$0.isShell } }
    private var preferences: PreferencesDocument? { environment.preferences?.document }

    private func path(_ agent: AgentDescriptor) -> String? {
        agent.cliCommand.flatMap { environment.launchers.resolve($0, override: preferences?.cliPaths?[agent.kind.rawValue]) }
    }

    private func isEnabled(_ agent: AgentDescriptor) -> Bool {
        AgentRegistry.builtin.enabledKinds(preferences?.enabledAgents).contains(agent.kind)
    }

    var body: some View {
        let detected = agents.filter { path($0) != nil }.count
        let active = agents.filter { path($0) != nil && isEnabled($0) }.count
        VStack(alignment: .leading, spacing: metrics.size(16)) {
            OnboardingWebIntro(title: "onboarding.web.agentsTitle",
                               subtitle: Text(verbatim: format("onboarding.web.agentsFound", detected)))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: metrics.size(10)), count: 3),
                      spacing: metrics.size(10)) {
                ForEach(agents) { agent in
                    OnboardingWebAgentCard(agent: agent, path: path(agent), enabled: isEnabled(agent)) { on in
                        environment.preferences?.update {
                            $0.enabledAgents = AgentRegistry.builtin.enabled($0.enabledAgents, setting: agent.kind, on: on)
                        }
                    }
                }
            }
            .id(scan)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding.agents")
            HStack(spacing: metrics.size(10)) {
                Text(verbatim: format("onboarding.web.agentsEnabledOf", active, agents.count))
                    .frame(maxWidth: .infinity, alignment: .leading)
                OnboardingHover { hovering in
                    Button {
                        environment.launchers.invalidate()
                        scan += 1
                    } label: {
                        Text("onboarding.web.agentsRescan")
                            .foregroundStyle(theme[hovering ? .fg : .fgMuted])
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(theme[.border]).frame(height: metrics.size(1))
                            }
                    }
                    .buttonStyle(.plain)
                }
                .accessibilityIdentifier("onboarding.agents.rescan")
            }
            .font(metrics.font(size: 11.5)).foregroundStyle(theme[.fgFaint])
        }
    }
}

private struct OnboardingWebAgentCard: View {
    let agent: AgentDescriptor
    private let path: String?
    private let enabled: Bool
    private let toggle: (Bool) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @State private var version: String?
    @State private var latest: String?
    @State private var probing = false
    @State private var sheet: AgentInstallSheet.Mode?

    private var installed: Bool { path != nil }
    private var on: Bool { installed && enabled }
    private var outdated: Bool {
        guard let version, let latest else { return false }
        return AgentVersions.isOutdated(version, latest: latest)
            && AgentInstallCatalog.npmPackage(for: agent.kind) != nil
    }

    var body: some View {
        OnboardingHover { hovering in
            VStack(spacing: metrics.size(8)) {
                AgentLogo(agent: agent.kind.rawValue, size: 26)
                    .frame(height: metrics.size(26))
                Text(verbatim: agent.displayName)
                    .font(metrics.font(size: 12.5)).lineLimit(1).foregroundStyle(theme[.fg])
                state
                if outdated {
                    Button("agentInstall.updateEllipsis") { sheet = .update }
                        .buttonStyle(OnboardingWebButtonStyle(kind: .normal))
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, metrics.size(16)).padding(.horizontal, metrics.size(10)).padding(.bottom, metrics.size(13))
            .background(theme[on ? .surfaceCardSelected : .surfaceCardDefault],
                        in: RoundedRectangle(cornerRadius: metrics.radius(.lg)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.lg))
                .strokeBorder(theme[on ? .accentBorder : hovering && installed ? .borderStrong : .border],
                              lineWidth: metrics.size(1)))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark").font(metrics.font(size: 10, weight: .bold))
                    .foregroundStyle(theme[.accentOn])
                    .frame(width: metrics.size(16), height: metrics.size(16))
                    .background(theme[.accent], in: Circle())
                    .padding(.top, metrics.size(7)).padding(.trailing, metrics.size(8))
                    .opacity(on ? 1 : 0)
            }
            .opacity(installed ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: metrics.radius(.lg)))
            .onTapGesture { if installed { toggle(!on) } }
            .animation(metrics.reducesMotion ? nil : .easeOut(duration: 0.12), value: on)
        }
        .help(path ?? String(localized: "onboarding.web.agentNotFoundPath"))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("onboarding.agent.\(agent.kind.rawValue)")
        .task(id: path) { await probe() }
        .gitWebSheet(item: $sheet, width: 480, onDismiss: { environment.launchers.invalidate(); Task { await probe() } }) { mode in
            AgentInstallSheet(agent: agent, mode: mode)
                .environment(environment)
                .environment(\.theme, theme)
                .environment(\.metrics, metrics)
        }
    }

    @ViewBuilder
    private var state: some View {
        if installed {
            Text(verbatim: probing ? String(localized: "onboarding.web.agentChecking")
                 : version.map { "v\($0)" } ?? String(localized: "onboarding.web.agentReady"))
                .font(metrics.font(size: 10.5)).foregroundStyle(theme[.fgFaint])
        } else if AgentInstallCatalog.entries[agent.kind] != nil {
            Button("agentInstall.installEllipsis") { sheet = .install }
                .buttonStyle(OnboardingWebButtonStyle(kind: .normal))
                .disabled(environment.installer.isBusy)
                .accessibilityIdentifier("onboarding.agent.install.\(agent.kind.rawValue)")
        } else {
            Text("onboarding.web.agentNotFoundPath").font(metrics.font(size: 10.5)).foregroundStyle(theme[.fgFaint])
        }
    }

    private func probe() async {
        version = nil
        guard let path else { return }
        probing = true
        version = await CLIVersion.probe(path)
        probing = false
        latest = await AgentVersions.latest(for: agent.kind)
    }
}

