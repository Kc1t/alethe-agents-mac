import AletheAgents
import AletheDesign
import AletheModel
import SwiftUI

struct TimeAnalytics: View {
    enum Range: String, CaseIterable, Identifiable {
        case today, week, month, all
        var id: Self { self }
        var days: Int? { if case .today = self {
            1
        } else if case .week = self {
            7
        } else if case .month = self {
            30
        } else {
            nil
        } }
        var title: LocalizedStringKey {
            if case .today = self {
                "home.time.today"
            } else if case .week = self {
                "home.time.7d"
            } else if case .month = self {
                "home.time.30d"
            } else {
                "home.time.all"
            }
        }
    }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var range = Range.today
    @State private var summary = ActivityTotals()
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        let totals = summary.totals
        VStack(alignment: .leading, spacing: metrics.space(.l)) {
            HStack {
                VStack(alignment: .leading, spacing: metrics.space(.xxs)) {
                    Group {
                        if metrics.isWebInterface {
                            Text("home.time").textCase(.lowercase).font(metrics.font(size: 12, weight: .semibold))
                        } else { HomeSectionHeader(title: "home.time") }
                    }
                    Text("home.time.subtitle").font(metrics.isWebInterface ? metrics.font(size: 9) :
                        metrics.font(.footnote)).foregroundStyle(theme[.textTertiary])
                }
                Spacer()
                Button {
                    Task { await refresh() }
                } label: { Image(systemName: "arrow.clockwise").webProfileSized(14) }
                    .buttonStyle(.borderless)
                    .help(Text("home.refresh"))
                    .accessibilityLabel(Text("home.refresh"))
                if metrics.isWebInterface {
                    HStack(spacing: metrics.size(2)) {
                        ForEach(Range.allCases) { option in
                            Button { range = option } label: {
                                Text(option.title).font(metrics.monoFont(size: 9))
                                    .padding(.horizontal, metrics.size(8)).frame(height: metrics.size(26))
                                    .foregroundStyle(theme[range == option ? .fg : .textTertiary])
                                    .background(theme[.accentSoft].opacity(range == option ? 1 : 0),
                                                in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
                                    .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm))
                                        .strokeBorder(theme[.accentBorder].opacity(range == option ? 1 : 0), lineWidth: metrics.size(1)))
                            }.buttonStyle(.plain)
                        }
                    }
                    .accessibilityIdentifier("home.time.range")
                } else {
                    Picker("home.time", selection: $range) {
                        ForEach(Range.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("home.time.range")
                }
            }
            (metrics.isWebInterface
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: metrics.size(7)))
                : AnyLayout(HStackLayout(alignment: .top, spacing: metrics.space(.m)))) {
                if metrics.isWebInterface {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: metrics.size(7)),
                        count: contentWidth > metrics.size(900) ? 4 : 2), spacing: metrics.size(7)) {
                        metric("home.time.active", totals.userActiveMs,
                               detail: String(format: String(localized: "home.time.focused"), HomeFormat.duration(ms: totals.appFocusedMs)))
                        metric("home.time.agents", totals.agentWallMs,
                               detail: String(format: String(localized: "home.time.agentSum"), HomeFormat.duration(ms: totals.agentSumMs)))
                        metric("home.time.background", totals.agentBackgroundMs,
                               detail: String(format: String(localized: "home.time.parallel"),
                                   HomeFormat.duration(ms: totals.parallelMs), Int(totals.peakConcurrent)))
                        metric("home.time.idle", totals.userIdleMs,
                               detail: String(format: String(localized: "home.time.noAgent"),
                                   HomeFormat.duration(ms: totals.appOpenMs &- min(totals.agentWallMs, totals.appOpenMs))))
                    }
                } else {
                    metric("home.time.active", totals.userActiveMs,
                           detail: String(format: String(localized: "home.time.focused"), HomeFormat.duration(ms: totals.appFocusedMs)))
                    metric("home.time.agents", totals.agentWallMs,
                           detail: String(format: String(localized: "home.time.agentSum"), HomeFormat.duration(ms: totals.agentSumMs)))
                    metric("home.time.background", totals.agentBackgroundMs,
                           detail: String(format: String(localized: "home.time.parallel"),
                               HomeFormat.duration(ms: totals.parallelMs), Int(totals.peakConcurrent)))
                    metric("home.time.idle", totals.userIdleMs,
                           detail: String(format: String(localized: "home.time.noAgent"),
                                          HomeFormat.duration(ms: totals.appOpenMs &- min(totals.agentWallMs, totals.appOpenMs))))
                }
            }
            (metrics.isWebInterface && contentWidth <= metrics.size(900)
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: metrics.size(14)))
                : AnyLayout(HStackLayout(alignment: .top, spacing: metrics.space(.xxl)))) {
                breakdown("home.time.byAgent", rows: summary.agents.sorted { $0.value.workingMs > $1.value.workingMs }.map { key, value in
                    (AgentLabels.name(for: key), value.workingMs,
                     String(format: String(localized: "home.time.backgroundShort"), HomeFormat.duration(ms: value.backgroundMs)))
                })
                breakdown("home.time.byProject", rows: summary.projects
                    .sorted { $0.value.activeMs + $0.value.agentSumMs > $1.value.activeMs + $1.value.agentSumMs }
                    .prefix(5).map { key, value in
                        (projectName(key), value.activeMs + value.agentWallMs,
                         String(format: String(localized: "home.time.projectDetail"),
                                HomeFormat.duration(ms: value.activeMs), HomeFormat.duration(ms: value.agentSumMs)))
                    })
            }
            Text(String(format: String(localized: "home.time.localNote"), TimeZone.current.identifier))
                .font(metrics.font(.caption)).foregroundStyle(theme[.textTertiary])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(HomeTimeSurface())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .task(id: TaskKey(range: range, revision: environment.activity.revision)) {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.time")
    }

    private func refresh() async {
        summary = await environment.activity.currentSummary(
            dates: range.days.map { ActivityStats.lastDays($0) } ?? [])
    }

    private struct TaskKey: Hashable { var range: Range; var revision: Int }

    private func projectName(_ id: String) -> String {
        if id == ActivityStats.unassigned { return String(localized: "home.time.unassigned") }
        return environment.workspace?.document.project(ProjectID(rawValue: id))?.name ?? String(localized: "home.time.removedProject")
    }

    private func metric(_ title: LocalizedStringKey, _ ms: UInt64, detail: String) -> some View {
        VStack(alignment: .leading, spacing: metrics.size(metrics.isWebInterface ? 4 : 2)) {
            Text(title).textCase(metrics.isWebInterface ? .uppercase : nil).font(metrics.isWebInterface ?
                metrics.font(size: 10) : metrics.font(.footnote)).foregroundStyle(theme[.textSecondary])
            Text(verbatim: HomeFormat.duration(ms: ms)).font(metrics.isWebInterface ? metrics.monoFont(size: 20,
                weight: .semibold) : metrics.font(.title2).monospacedDigit())
            Text(verbatim: detail).font(metrics.isWebInterface ? metrics.font(size: 9) : metrics.font(.caption))
                .foregroundStyle(theme[.textTertiary])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(metrics.size(metrics.isWebInterface ? 10 : 12))
        .background(theme[metrics.isWebInterface ? .bg : .bgSunken].opacity(metrics.isWebInterface ? 0.72 : 1),
            in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
        .overlay {
            if metrics.isWebInterface {
                RoundedRectangle(cornerRadius: metrics.radius(.md))
                    .strokeBorder(theme[.borderSubtle], lineWidth: metrics.size(1))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func breakdown(_ title: LocalizedStringKey, rows: [(String, UInt64, String)]) -> some View {
        VStack(alignment: .leading, spacing: metrics.space(.s)) {
            Text(title).textCase(metrics.isWebInterface ? .uppercase : nil).font(metrics.isWebInterface ?
                metrics.font(size: 10) : metrics.font(.footnote).weight(.medium)).foregroundStyle(theme[.textSecondary])
            if rows.isEmpty {
                Text("home.time.empty").font(metrics.isWebInterface ? metrics.font(size: 10) : metrics.font(.footnote))
                    .foregroundStyle(theme[.textTertiary])
                    .frame(maxWidth: .infinity, alignment: metrics.isWebInterface ? .center : .leading)
                    .padding(.vertical, metrics.isWebInterface ? metrics.size(13) : 0)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(verbatim: row.0).lineLimit(1)
                    Spacer()
                    Text(verbatim: HomeFormat.duration(ms: row.1)).monospacedDigit()
                    Text(verbatim: row.2).foregroundStyle(theme[.textTertiary])
                }
                .font(metrics.font(.footnote))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
