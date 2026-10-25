import AletheDesign
import AletheModel
import SwiftUI

extension Notification.Name {
    static let aletheOpenTitleBarMemory = Notification.Name("alethe.openTitleBarMemory")
}

struct WebTitleBarMemoryPill: View {
    @Environment(AppEnvironment.self) var environment
    @Environment(\.metrics) var metrics
    @Environment(\.theme) var theme
    @State private var hovering = false

    var body: some View {
        let available = environment.resources.system.availableMB
        let pressure: ThemeToken = available < 512 ? .statusOffline : available < 1024 ? .statusWorking :
            available < 2048 ? .statusWaiting : .borderStrong
        Button { NotificationCenter.default.post(name: .aletheOpenTitleBarMemory, object: nil) } label: {
            Text(verbatim: MemoryIndicator.pillText(count: environment.resources.aiTerminalCount,
                                                    totalMB: environment.resources.appMB + environment.resources.terminalsMB))
                .font(metrics.monoFont(size: 11)).monospacedDigit()
                .foregroundStyle(theme[hovering ? .fg : .fgMuted])
                .padding(.horizontal, metrics.size(8)).padding(.vertical, metrics.size(2))
                .frame(minHeight: metrics.size(22))
                .background(theme[available < 256 ? .statusOfflineSoft : .bgSunken].opacity(metrics.style == .clean ? 0 : 1),
                            in: RoundedRectangle(cornerRadius: metrics.size(metrics.style == .clean ? 4 : 8)))
                .overlay(RoundedRectangle(cornerRadius: metrics.size(metrics.style == .clean ? 4 : 8))
                    .strokeBorder(theme[hovering ? .borderStrong : pressure].opacity(metrics.style == .clean ||
                        (!hovering && available >= 2048) ? 0 : 1), lineWidth: metrics.size(1)))
        }
        .buttonStyle(.plain).fixedSize().onHover { hovering = $0 }
        .webOpacityPulse(period: available < 256 ? 0.8 : 1.5, active: available < 512)
        .help(Text("titlebar.memory.open"))
        .accessibilityLabel(Text(MemoryIndicator.accessibilityText(
            memory: MemoryIndicator.format(environment.resources.appMB + environment.resources.terminalsMB),
            count: environment.resources.aiTerminalCount)))
        .accessibilityIdentifier("memory.indicator")
    }
}

struct WebTitleBarMemory: View {
    let close: () -> Void
    @Environment(AppEnvironment.self) var environment
    @Environment(\.metrics) var metrics
    @Environment(\.theme) var theme
    @State var hoverIndex: Int?
    @State var tab: MemoryTab = .overview

    private enum Level { case healthy, warning, critical }
    var history: [ResourceMonitor.Sample] { environment.resources.history }
    var latest: ResourceMonitor.Sample? { history.last }

    var windowed: [ResourceMonitor.Sample] {
        guard let latest else { return [] }
        let recent = history.filter { latest.timestamp.timeIntervalSince($0.timestamp) <= 600 }
        return recent.count >= 2 ? recent : history
    }

    var level: Level {
        guard let latest, latest.systemTotalMB > 0 else { return .healthy }
        if latest.systemAvailableMB <= max(512, latest.systemTotalMB * 0.05) { return .critical }
        if latest.systemAvailableMB <= max(1024, latest.systemTotalMB * 0.1) { return .warning }
        return .healthy
    }

    var growth: Double {
        guard let first = windowed.first, let last = windowed.last, windowed.count >= 2 else { return 0 }
        return last.totalMB - first.totalMB
    }

    var body: some View {
        GitWebModal(close: close, closeIdentifier: "memory.close") {
            Text("memModal.title")
        } content: {
            VStack(alignment: .leading, spacing: metrics.size(12)) {
                tabStrip
                if case .overview = tab {
                    overview
                } else {
                    aiPanel
                }
            }
        } footer: {
            Spacer(minLength: 0)
            Button { environment.resources.clearHistory() } label: {
                Label { Text("memModal.clear") } icon: { Image(systemName: "trash").font(metrics.font(size: 14)) }
                    .labelStyle(.titleAndIcon)
            }
            .disabled(history.isEmpty)
            .accessibilityIdentifier("memory.clearHistory")
        }
        .accessibilityIdentifier("memory.details")
    }

    private var tabStrip: some View {
        HStack(spacing: metrics.size(4)) {
            ForEach(MemoryTab.allCases) { item in
                Button { tab = item } label: {
                    HStack(spacing: metrics.size(6)) {
                        Text(item.title)
                        if item == .ai {
                            Text(verbatim: "\(environment.resources.aiTerminalCount)")
                                .font(metrics.monoFont(size: 10, weight: .bold))
                                .padding(.horizontal, metrics.size(6)).padding(.vertical, metrics.size(1))
                                .background(theme[.bgSunken], in: Capsule())
                        }
                    }
                    .font(metrics.font(size: 12, weight: tab == item ? .semibold : .regular))
                    .foregroundStyle(theme[tab == item ? .fg : .fgMuted])
                    .padding(.horizontal, metrics.size(12)).padding(.vertical, metrics.size(6))
                    .background(tab == item ? theme[.bgSunken] : Color.clear, in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
                .accessibilityIdentifier("memory.tab.\(item.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("memory.tabs")
    }

    @ViewBuilder private var overview: some View {
        if let crash = environment.diagnostics.crashNotice { crashPanel(crash) }
        healthPanel
        summary
        historyPanel
        HStack(alignment: .top, spacing: metrics.size(12)) {
            bottlenecksPanel.frame(maxWidth: .infinity)
            compositionPanel.frame(maxWidth: .infinity)
        }
        runtimePanel
        samplesPanel
    }

    private var aiPanel: some View {
        let sessions = environment.resources.terminals.filter(\.isAgent)
        return panel {
            panelHeader("memModal.tab.ai", subtitle: format("memory.ai.header", "\(sessions.count)",
                                                           mb(sessions.reduce(0) { $0 + $1.memoryMB }))) {
                Image(systemName: "sparkles").font(metrics.font(size: 16))
            }
            AIProcessList()
        }
    }

    func panel<Content: View>(border: ThemeToken = .border, tint: ThemeToken? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(metrics.size(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.map { theme[$0].opacity(0.08) } ?? theme[.bg],
                        in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md)).strokeBorder(theme[border], lineWidth: metrics.size(1)))
    }

    func panelHeader<Trailing: View>(_ title: LocalizedStringKey, subtitle: String,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: metrics.size(12)) {
            VStack(alignment: .leading, spacing: metrics.size(3)) {
                Text(title).font(metrics.font(size: 13, weight: 650)).foregroundStyle(theme[.fg])
                Text(verbatim: subtitle).font(metrics.font(size: 11)).foregroundStyle(theme[.fgMuted])
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing().foregroundStyle(theme[.fgMuted])
        }
        .padding(.bottom, metrics.size(10))
    }

    private func crashPanel(_ crash: CrashNotice) -> some View {
        panel(border: .statusOffline, tint: .statusOffline) {
            panelHeader("memModal.crash.title",
                        subtitle: format("memModal.crash.subtitle",
                            crash.previous.startedAt.formatted(date: .abbreviated, time: .shortened))) {
                Image(systemName: "exclamationmark.triangle").font(metrics.font(size: 16))
                    .foregroundStyle(theme[.statusOffline])
            }
            Button { environment.diagnostics.openLogsFolder() } label: {
                Label { Text("memModal.openLogs") } icon: { Image(systemName: "folder").font(metrics.font(size: 14)) }
            }
            .accessibilityIdentifier("memory.openLogs")
        }
    }

    private var healthPanel: some View {
        let token: ThemeToken = if case .healthy = level {
            .statusActive
        } else if case .warning = level {
            .statusWaiting
        } else {
            .statusOffline
        }
        let title: LocalizedStringKey = if case .healthy = level {
            "memModal.healthy.title"
        } else if case .warning = level {
            "memModal.warning.title"
        } else {
            "memModal.critical.title"
        }
        let bodyFormat: String = if case .healthy = level {
            String(localized: "memModal.healthy.body")
        } else if case .warning = level {
            String(localized: "memModal.warning.body")
        } else {
            String(localized: "memModal.critical.body")
        }
        return panel(border: token, tint: token) {
            HStack(alignment: .top, spacing: metrics.size(12)) {
                VStack(alignment: .leading, spacing: metrics.size(3)) {
                    Text(title).font(metrics.font(size: 13, weight: 650)).foregroundStyle(theme[.fg])
                    if let latest {
                        Text(verbatim: String(format: bodyFormat, mb(latest.systemAvailableMB), mb(latest.systemTotalMB)))
                            .font(metrics.font(size: 11)).foregroundStyle(theme[.fgMuted])
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("memModal.waiting").font(metrics.font(size: 11)).foregroundStyle(theme[.fgMuted])
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: level == .healthy ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(metrics.font(size: 16)).foregroundStyle(theme[token])
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("memory.health")
    }

    private var summary: some View {
        let peak = history.map(\.totalMB).max()
        let average = windowed.isEmpty ? 0 : windowed.reduce(0) { $0 + $1.totalMB } / Double(windowed.count)
        let trendToken: ThemeToken = growth >= 120 ? .statusOffline : growth <= -80 ? .statusWorking : .fg
        return HStack(spacing: metrics.size(8)) {
            metric("memModal.now", "waveform.path.ecg", latest.map { mb($0.totalMB) } ?? "-")
            metric("memModal.peak", "display", peak.map(mb) ?? "-")
            metric("memModal.avg", "cpu", history.isEmpty ? "-" : mb(average))
            metric("memModal.trend", "square.3.layers.3d", (growth >= 0 ? "+" : "") + mb(growth), token: trendToken)
        }
    }

    private func metric(_ title: LocalizedStringKey, _ symbol: String, _ value: String, token: ThemeToken = .fg) -> some View {
        HStack(spacing: metrics.size(8)) {
            Image(systemName: symbol).font(metrics.font(size: 16)).foregroundStyle(theme[.fgMuted])
                .frame(width: metrics.size(18))
            VStack(alignment: .leading, spacing: metrics.size(2)) {
                Text(title).font(metrics.font(size: 11)).foregroundStyle(theme[.fgMuted]).lineLimit(1)
                Text(verbatim: value).font(metrics.monoFont(size: 14, weight: .bold))
                    .foregroundStyle(theme[token]).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(metrics.size(10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
    }


}

