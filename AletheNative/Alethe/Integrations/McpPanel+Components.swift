import AletheDesign
import AletheIntegrations
import AletheModel
import AlethePluginKit
import SwiftUI

extension McpSnapshotIssue {
    private static let titleValues: [McpSnapshotIssue: String] = [
        .unsupported: "mcp.diag.unsupported",
        .unreadable: "mcp.diag.unreadable",
        .missing: "mcp.diag.missing",
    ]

    var title: LocalizedStringKey {
        LocalizedStringKey(Self.titleValues[self] ?? "mcp.diag.readOnly")
    }
}

extension McpHealthStatus {
    private static let titleValues: [McpHealthStatus: String] = [
        .connected: "mcp.health.connected",
        .failed: "mcp.health.failed",
        .needsAuth: "mcp.health.needsAuth",
        .disabled: "mcp.health.disabled",
    ]

    var title: LocalizedStringKey {
        LocalizedStringKey(Self.titleValues[self] ?? "mcp.health.unknown")
    }

    private static let tokenValues: [McpHealthStatus: ThemeToken] = [
        .connected: .statusActive,
        .failed: .statusStopped,
        .needsAuth: .statusWaiting,
        .disabled: .statusIdle,
    ]

    var token: ThemeToken {
        Self.tokenValues[self] ?? .statusIdle
    }
}

struct McpHealthDot: View {
    let status: McpHealthStatus
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        Circle()
            .fill(theme[status.token])
            .frame(width: metrics.size(7), height: metrics.size(7))
            .help(Text(status.title))
            .accessibilityLabel(Text(status.title))
    }
}

struct McpBadge: View {
    let title: LocalizedStringKey
    var token: ThemeToken = .textSecondary
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        Text(title)
            .lineLimit(metrics.isWebInterface ? 1 : nil)
            .font(metrics.isWebInterface ? metrics.font(size: 10) : metrics.font(.caption))
            .foregroundStyle(theme[metrics.isWebInterface && token == .textSecondary ? .fgFaint : token])
            .padding(.horizontal, metrics.isWebInterface ? metrics.size(6) : metrics.space(.xs))
            .padding(.vertical, metrics.isWebInterface ? metrics.size(3) : metrics.space(.xxs))
            .background(theme[.bgSunken].opacity(metrics.isWebInterface ? 0 : 1), in: Capsule())
            .overlay {
                if metrics.isWebInterface { Capsule().strokeBorder(theme[.border], lineWidth: metrics.size(1)) }
            }
    }
}

struct McpAgentDots: View {
    let present: [McpAgent]
    let missing: [McpAgent]
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.isWebInterface ? metrics.size(3) : metrics.space(.xxs)) {
            ForEach(McpAgent.allCases.filter { present.contains($0) || missing.contains($0) }, id: \.self) { agent in
                if metrics.isWebInterface {
                    AgentLogo(agent: agent.rawValue, size: 13)
                        .opacity(present.contains(agent) ? 1 : 0.22)
                        .saturation(present.contains(agent) ? 1 : 0)
                } else if present.contains(agent) {
                    Circle().fill(theme[agent.colorToken])
                        .frame(width: metrics.size(7), height: metrics.size(7))
                } else {
                    Circle().strokeBorder(theme[agent.colorToken], lineWidth: 1)
                        .frame(width: metrics.size(7), height: metrics.size(7))
                }
            }
        }
        .fixedSize(horizontal: metrics.isWebInterface, vertical: false)
        .accessibilityHidden(true)
    }
}

struct McpWebRowBackground: ViewModifier {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @State private var hovering = false
    func body(content: Content) -> some View {
        content.background(
            theme[.panelHover].opacity(metrics.isWebInterface && hovering ? 1 : 0), in: RoundedRectangle(cornerRadius: metrics.radius(.md))
        )
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radius(.md))
                .strokeBorder(theme[.borderSubtle].opacity(metrics.isWebInterface && hovering ? 1 : 0), lineWidth: metrics.size(1))
        }
        .animation(metrics.isWebInterface ? Motion.sidebarColor(reduceMotion: metrics.reducesMotion) : nil, value: hovering)
        .onHover { hovering = $0 }
    }
}

struct WebMcpEmpty: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: metrics.size(10)) {
            Image(systemName: "powerplug").font(metrics.font(size: 20))
                .foregroundStyle(theme[.accent])
                .frame(width: metrics.size(56), height: metrics.size(56))
                .background(theme[.accentSoft], in: RoundedRectangle(cornerRadius: metrics.size(18)))
                .overlay(RoundedRectangle(cornerRadius: metrics.size(18)).strokeBorder(theme[.accentBorder], lineWidth: metrics.size(1)))
            VStack(spacing: metrics.size(6)) {
                Text(title).font(metrics.font(size: 15, weight: 650)).tracking(metrics.size(-0.3))
                if let detail {
                    Text(detail).font(metrics.font(size: 12)).foregroundStyle(theme[.fgMuted])
                        .lineSpacing(metrics.size(3))
                }
            }
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme[.fg])
        .padding(.vertical, metrics.size(20)).padding(.horizontal, metrics.size(18))
        .frame(maxWidth: .infinity)
        .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.lg)))
        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.lg)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
        .padding(metrics.size(12))
    }
}

struct McpRefreshPresentation: ViewModifier {
    @Environment(\.metrics) private var metrics
    func body(content: Content) -> some View {
        if metrics.isWebInterface {
            content.buttonStyle(AletheSidebarUtilityStyle(disabledOpacity: 1, faintWhenDisabled: true))
        } else { content.buttonStyle(.borderless) }
    }
}

struct McpFilterPresentation: ViewModifier {
    let selected: Bool
    @Environment(\.metrics) private var metrics
    func body(content: Content) -> some View {
        if metrics.isWebInterface {
            content.buttonStyle(AletheSidebarFilterStyle(selected: selected, kind: .agent))
        } else {
            content.buttonStyle(.plain)
        }
    }
}
