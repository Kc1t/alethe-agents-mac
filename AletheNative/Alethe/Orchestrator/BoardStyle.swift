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
    var token: ThemeToken {
        switch self {
        case .running: .statusWorking
        case .queued, .interrupted, .blocked: .statusWaiting
        case .failed: .statusOffline
        case .finished: .statusStopped
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .blocked: "orchestrator.lane.blocked"
        case .running: "orchestrator.lane.running"
        case .queued: "orchestrator.lane.queued"
        case .interrupted: "orchestrator.lane.interrupted"
        case .failed: "orchestrator.lane.failed"
        case .finished: "orchestrator.lane.finished"
        }
    }

    var explanation: LocalizedStringKey? {
        switch self {
        case .blocked: "orchestrator.blockedTitle"
        case .interrupted: "orchestrator.interruptedTitle"
        default: nil
        }
    }
}

extension JobStatus {
    var title: LocalizedStringKey {
        switch self {
        case .queued: "orchestrator.status.queued"
        case .running: "orchestrator.status.running"
        case .blocked: "orchestrator.status.blocked"
        case .done: "orchestrator.status.done"
        case .failed: "orchestrator.status.failed"
        case .cancelled: "orchestrator.status.cancelled"
        case .released: "orchestrator.status.released"
        case .interrupted: "orchestrator.status.interrupted"
        }
    }
}

extension RunAttention {
    var text: String {
        let key: String.LocalizationValue = switch lane {
        case .blocked: "orchestrator.runBlocked"
        case .failed: "orchestrator.runFailed"
        case .interrupted: "orchestrator.runInterrupted"
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
