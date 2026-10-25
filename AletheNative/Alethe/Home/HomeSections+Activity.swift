import AletheAgents
import AletheDesign
import AletheModel
import SwiftUI

struct ActivityGraph: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @Binding var days: [ActivityDays.Day]
    @State private var loading = true
    nonisolated static let dayCount = 91

    var body: some View {
        if metrics.isWebInterface { webBody } else { nativeBody }
    }

    private var nativeBody: some View {
        VStack(alignment: .leading, spacing: metrics.space(.m)) {
            HStack(spacing: metrics.space(.m)) {
                HomeSectionHeader(title: "home.activity")
                if !days.isEmpty {
                    Text(String(format: String(localized: "home.activity.total"), days.reduce(0) { $0 + $1.count }))
                    Label { Text(String(format: String(localized: "home.activity.streak"),
                        ActivityDays.streak(days))) } icon: { Image(systemName: "flame").webProfileSized(14) }
                        .accessibilityIdentifier("home.activity.streak")
                }
                if let delta {
                    Text(verbatim: "\(delta >= 0 ? "▲" : "▼") \(Int(abs(delta).rounded()))%")
                        .padding(.horizontal, metrics.space(.s))
                        .padding(.vertical, metrics.space(.xxs))
                        .background(theme[.bgSunken], in: Capsule())
                        .help(Text("home.activity.delta"))
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise").webProfileSized(14) }
                    .buttonStyle(.borderless)
                    .help(Text("home.refresh"))
                    .accessibilityLabel(Text("home.refresh"))
            }
            .font(metrics.font(.footnote))
            .foregroundStyle(theme[.textSecondary])
            grid
            HStack(spacing: metrics.space(.xs)) {
                Text("home.activity.days")
                Spacer()
                Text("home.activity.less")
                ForEach(0..<5) { level in cell(level) }
                Text("home.activity.more")
            }
            .font(metrics.font(.caption))
            .foregroundStyle(theme[.textTertiary])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aletheCard()
        .task { await load() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.activity")
    }

    private var webBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                webHeader(detailed: true)
                webHeader(detailed: false)
            }.padding(.bottom, metrics.size(14))
            HStack(alignment: .firstTextBaseline, spacing: metrics.size(4)) {
                Text(verbatim: loading ? "—" : days.reduce(0) { $0 + $1.count }.formatted())
                    .font(metrics.monoFont(size: 28, weight: .semibold)).tracking(metrics.size(-0.56))
                Text("home.web.messages").font(metrics.monoFont(size: 16, weight: .medium))
                    .foregroundStyle(theme[.textQuaternary]).lineLimit(1)
                Spacer(minLength: 0)
                if let delta {
                    Text(verbatim: "\(delta >= 0 ? "▲" : "▼") \(Int(abs(delta).rounded()))%")
                        .font(metrics.monoFont(size: 10.5, weight: .medium))
                        .padding(.horizontal, metrics.size(8)).padding(.vertical, metrics.size(4))
                        .overlay(RoundedRectangle(cornerRadius: metrics.size(7))
                            .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                }
            }
            Text("home.web.lastDays").font(metrics.monoFont(size: 11)).foregroundStyle(theme[.textTertiary])
                .padding(.top, metrics.size(6))
            VStack(spacing: metrics.size(9)) {
                if loading || days.isEmpty {
                    Text(loading ? "home.bottom.activityLoading" : "home.bottom.activityEmpty")
                        .font(metrics.font(size: 11)).foregroundStyle(theme[.textQuaternary])
                        .frame(maxWidth: .infinity, minHeight: metrics.size(88))
                } else {
                    webGrid
                    HStack(spacing: metrics.size(3)) {
                        Spacer()
                        Text("home.activity.less")
                        ForEach(0..<5) { level in
                            RoundedRectangle(cornerRadius: metrics.size(2))
                                .fill(theme[level == 0 ? .bgElevated : .statusWorking].opacity(level == 0 ? 1 : Double(level) * 0.25))
                                .frame(width: metrics.size(8), height: metrics.size(8))
                        }
                        Text("home.activity.more")
                    }.font(metrics.font(size: 9)).foregroundStyle(theme[.textQuaternary])
                }
            }.padding(.top, metrics.size(16))
            HStack(spacing: metrics.size(6)) {
                AletheStatusDot(.statusWorking, side: 6)
                Text(String(format: String(localized: "home.activity.streak"), ActivityDays.streak(days)))
                    .accessibilityIdentifier("home.activity.streak").lineLimit(1)
                Spacer(minLength: 0)
                Text(String(format: String(localized: "home.activity.total"), days.reduce(0) { $0 + $1.count }))
                    .foregroundStyle(theme[.textQuaternary]).lineLimit(1)
            }
            .font(metrics.monoFont(size: 10.5)).foregroundStyle(theme[.textTertiary])
            .padding(.top, metrics.size(12))
            .overlay(alignment: .top) { theme[.borderSubtle].frame(height: metrics.size(1)) }
            .padding(.top, metrics.size(14))
        }
        .modifier(HomeWebCard())
        .task { await load() }
        .accessibilityElement(children: .contain).accessibilityIdentifier("home.activity")
    }

    private func webHeader(detailed: Bool) -> some View {
        HStack(spacing: metrics.size(9)) {
            HomeWebBadge(symbol: "waveform.path", token: .statusWorking)
            Text("home.activity").textCase(.lowercase).font(metrics.font(size: 13.5, weight: .medium))
                .tracking(metrics.size(-0.135)).lineLimit(1)
            if detailed {
                Text("home.web.range").font(metrics.monoFont(size: 9.5))
                    .foregroundStyle(theme[.textTertiary])
                    .padding(.horizontal, metrics.size(6)).padding(.vertical, metrics.size(2))
                    .background(theme[.bgElevated], in: RoundedRectangle(cornerRadius: metrics.size(5)))
                    .overlay(RoundedRectangle(cornerRadius: metrics.size(5))
                        .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
            }
            Spacer(minLength: 0)
            if detailed, !loading, !days.isEmpty {
                HStack(spacing: metrics.size(5)) {
                    AletheStatusDot(.statusWorking, side: 6)
                    Text("home.web.live").font(metrics.monoFont(size: 9.5)).foregroundStyle(theme[.textTertiary])
                }.fixedSize()
            }
            HomeBottomRefreshButton(refreshing: loading) { await load() }
        }.frame(minHeight: metrics.size(26))
    }

    private var webGrid: some View {
        let peak = days.map(\.count).max() ?? 0
        return HStack(alignment: .top, spacing: metrics.size(4)) {
            VStack(alignment: .leading, spacing: metrics.size(2)) {
                ForEach(0..<7) { weekday in
                    Text(verbatim: weekday % 2 == 1 ? Calendar.current.shortWeekdaySymbols[weekday].lowercased() : "")
                        .font(metrics.monoFont(size: 9)).foregroundStyle(theme[.textQuaternary])
                        .frame(height: metrics.size(11))
                }
            }.padding(.trailing, metrics.size(2))
            HStack(alignment: .top, spacing: metrics.size(2)) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: metrics.size(2)) {
                        ForEach(Array(column.enumerated()), id: \.offset) { _, day in
                            if let day {
                                HomeActivityCell(level: Self.level(day.count, peak: peak))
                                    .help(Text(String(format: String(localized: "home.activity.tooltip"), day.count, day.date)))
                            } else {
                                Color.clear.frame(height: metrics.size(11))
                            }
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: String(localized: "home.activity.summary"),
                                        days.reduce(0) { $0 + $1.count }, ActivityDays.streak(days))))
    }

    private var delta: Double? {
        guard days.count >= 14 else { return nil }
        let recent = days.suffix(7).reduce(0) { $0 + $1.count }
        let previous = days.dropLast(7).suffix(7).reduce(0) { $0 + $1.count }
        return previous == 0 ? (recent > 0 ? 100 : 0) : Double(recent - previous) / Double(previous) * 100
    }

    private var grid: some View {
        let peak = days.map(\.count).max() ?? 0
        return HStack(alignment: .top, spacing: metrics.space(.xxs)) {
            VStack(alignment: .trailing, spacing: metrics.space(.xxs)) {
                ForEach(0..<7) { weekday in
                    Text(verbatim: metrics.isWebInterface ? (weekday % 2 == 1 ?
                        Calendar.current.shortWeekdaySymbols[weekday].lowercased() : "") : Calendar.current.shortWeekdaySymbols[weekday])
                        .font(metrics.font(size: 8))
                        .foregroundStyle(theme[.textTertiary])
                        .frame(height: metrics.size(11))
                }
            }
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: metrics.space(.xxs)) {
                    ForEach(Array(column.enumerated()), id: \.offset) { _, day in
                        if let day {
                            cell(Self.level(day.count, peak: peak))
                                .help(Text(String(format: String(localized: "home.activity.tooltip"), day.count, day.date)))
                        } else {
                            cell(nil)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: String(localized: "home.activity.summary"),
                                        days.reduce(0) { $0 + $1.count }, ActivityDays.streak(days))))
    }

    private var columns: [[ActivityDays.Day?]] {
        guard let first = days.first else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(identifier: "UTC") else {
            preconditionFailure("UTC time zone is unavailable")
        }
        calendar.timeZone = timeZone
        let date = ISO8601DateFormatter().date(from: first.date + "T00:00:00Z") ?? Date()
        let padding = calendar.component(.weekday, from: date) - 1
        let cells: [ActivityDays.Day?] = Array(repeating: nil, count: padding) + days.map(Optional.some)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    private func cell(_ level: Int?) -> some View {
        RoundedRectangle(cornerRadius: metrics.size(2))
            .fill(level.map { $0 == 0 ? theme[metrics.isWebInterface ? .bgElevated : .panelHover] :
                theme[metrics.isWebInterface ? .statusWorking : .accent].opacity((metrics.isWebInterface ? [0, 0.25,
                0.5, 0.75, 1] : [0, 0.3, 0.5, 0.75, 1])[$0]) } ?? .clear)
            .frame(width: metrics.isWebInterface ? nil : metrics.size(11), height: metrics.size(11))
            .frame(maxWidth: metrics.isWebInterface ? .infinity : nil)
    }

    static func level(_ count: Int, peak: Int) -> Int {
        guard count > 0, peak > 0 else { return 0 }
        let ratio = Double(count) / Double(peak)
        return ratio < 0.25 ? 1 : ratio < 0.5 ? 2 : ratio < 0.75 ? 3 : 4
    }

    private func load() async {
        loading = true
        let executable = environment.launchers.resolve("opencode", override: environment.preferences?.document.cliPaths?["opencode"])
        let database = await SessionCosts.openCodeDatabase(executable: executable)
        days = await Task.detached(priority: .utility) {
            ActivityDays.collect(days: Self.dayCount, openCodeDatabase: database)
        }.value
        loading = false
    }
}

