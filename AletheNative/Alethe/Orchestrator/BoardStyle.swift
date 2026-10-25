import AletheDesign
import AletheOrchestrator
import SwiftUI

struct BoardUnits {
    let metrics: Metrics
    let zoom: CGFloat

    var unit: CGFloat { metrics.scale * zoom }

    func space(_ space: Metrics.Space) -> CGFloat { space.rawValue * unit }
    func size(_ points: CGFloat) -> CGFloat { points * unit }
    func radius(_ radius: Metrics.Radius) -> CGFloat { metrics.radius(radius) * zoom }
    func font(_ style: TextStyle) -> Font { metrics.font(style, zoom: zoom) }
}

extension RunLane {
    private static let tokenValues: [RunLane: ThemeToken] = [
        .running: .statusWorking,
        .queued: .statusWaiting,
        .interrupted: .statusWaiting,
        .blocked: .statusWaiting,
        .failed: .statusOffline,
    ]

    var token: ThemeToken {
        Self.tokenValues[self] ?? .statusStopped
    }

    private static let titleValues: [RunLane: String] = [
        .blocked: "orchestrator.lane.blocked",
        .running: "orchestrator.lane.running",
        .queued: "orchestrator.lane.queued",
        .interrupted: "orchestrator.lane.interrupted",
        .failed: "orchestrator.lane.failed",
    ]

    var title: LocalizedStringKey {
        LocalizedStringKey(Self.titleValues[self] ?? "orchestrator.lane.finished")
    }

    private static let explanationValues: [RunLane: String] = [
        .blocked: "orchestrator.blockedTitle",
        .interrupted: "orchestrator.interruptedTitle",
    ]

    var explanation: LocalizedStringKey? {
        Self.explanationValues[self].map { LocalizedStringKey($0) }
    }
}

extension JobStatus {
    private static let titleValues: [JobStatus: String] = [
        .queued: "orchestrator.status.queued",
        .running: "orchestrator.status.running",
        .blocked: "orchestrator.status.blocked",
        .done: "orchestrator.status.done",
        .failed: "orchestrator.status.failed",
        .cancelled: "orchestrator.status.cancelled",
        .released: "orchestrator.status.released",
    ]

    var title: LocalizedStringKey {
        LocalizedStringKey(Self.titleValues[self] ?? "orchestrator.status.interrupted")
    }
}

extension RunAttention {
    var text: String {
        let key: String.LocalizationValue = if case .blocked = lane {
            "orchestrator.runBlocked"
        } else if case .failed = lane {
            "orchestrator.runFailed"
        } else {
            "orchestrator.runInterrupted"
        }
        return String(format: String(localized: key), count)
    }
}

struct BoardLaneDot: View {
    let lane: RunLane
    let size: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if lane == .interrupted {
                Circle().strokeBorder(theme[lane.token], lineWidth: max(1, size / 4))
            } else {
                Circle().fill(theme[lane.token])
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct BoardAgentGlyph: View {
    let agent: String?
    let size: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let agent, !agent.isEmpty {
                RoundedRectangle(cornerRadius: size / 4)
                    .fill(theme[AgentTokens.accent(for: agent)])
                    .frame(width: size * 0.7, height: size * 0.7)
                    .frame(width: size, height: size)
                    .help(Text(verbatim: String(format: String(localized: "orchestrator.agentTitle"), agent)))
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(theme[.textTertiary])
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

struct BoardChip: View {
    let text: String
    var symbol: String?
    var help: String?
    let units: BoardUnits
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: units.space(.xxs)) {
            if let symbol { Image(systemName: symbol) }
            Text(verbatim: text).monospacedDigit()
        }
        .font(units.font(.caption))
        .foregroundStyle(theme[.textSecondary])
        .padding(.horizontal, units.space(.xs))
        .padding(.vertical, units.size(1))
        .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: units.radius(.sm)))
        .help(help ?? "")
    }
}
