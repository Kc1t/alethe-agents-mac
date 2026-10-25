import AletheDesign
import AletheModel
import SwiftUI

extension WebTitleBarMemory {
    var runtimePanel: some View {
        let rows = environment.resources.terminals
        return panel {
            panelHeader("memModal.runtime", subtitle: format("memModal.runtimeSubtitle", "\(rows.count)", mb(environment.resources.terminalsMB))) {
                Text(verbatim: pressureLabel).font(metrics.monoFont(size: 11)).textCase(.uppercase)
                    .padding(.horizontal, metrics.size(7)).padding(.vertical, metrics.size(4))
                    .foregroundStyle(theme[pressureToken])
                    .background(theme[.bgSunken], in: Capsule())
                    .overlay(Capsule().strokeBorder(theme[pressureToken == .fgMuted ? .border : pressureToken], lineWidth: metrics.size(1)))
            }
            VStack(spacing: metrics.size(6)) {
                if rows.isEmpty {
                    Text("memModal.noRuntimes").font(metrics.font(size: 12)).foregroundStyle(theme[.fgMuted])
                        .frame(maxWidth: .infinity, minHeight: metrics.size(90))
                }
                ForEach(rows) { usage in
                    HStack(spacing: metrics.size(10)) {
                        Text(verbatim: terminalName(usage.tab)).foregroundStyle(theme[.fg]).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: mb(usage.memoryMB)).foregroundStyle(theme[.fg]).fontWeight(.bold)
                    }
                    .font(metrics.monoFont(size: 11))
                    .padding(.horizontal, metrics.size(10)).padding(.vertical, metrics.size(9))
                    .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
                    .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                }
            }
        }
    }

    var samplesPanel: some View {
        let rows = Array(history.suffix(12).reversed())
        return panel {
            panelHeader("memModal.latest", subtitle: String(localized: "memModal.latestSubtitle")) { EmptyView() }
            VStack(spacing: 0) {
                tableRow(["memModal.colTime", "memModal.colTotal", "memModal.bucketApp", "memModal.bucketPtys", "memModal.colProc"].map {
                    Text(LocalizedStringKey($0)) }, head: true)
                if rows.isEmpty {
                    Text("memModal.waitingFirst").font(metrics.font(size: 12)).foregroundStyle(theme[.fgMuted])
                        .frame(maxWidth: .infinity, minHeight: metrics.size(90))
                }
                ForEach(rows) { sample in
                    tableRow([Text(verbatim: time(sample.timestamp)), Text(verbatim: mb(sample.totalMB)).fontWeight(.semibold),
                              Text(verbatim: mb(sample.appMB)), Text(verbatim: mb(sample.terminalsMB)),
                              Text(verbatim: "\(sample.processCount)")], head: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius(.sm)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
        }
    }

    private func tableRow(_ cells: [Text], head: Bool) -> some View {
        HStack(spacing: metrics.size(8)) {
            ForEach(cells.indices, id: \.self) { index in
                cells[index].frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            }
        }
        .font(head ? metrics.font(size: 11, weight: 650) : metrics.monoFont(size: 11))
        .foregroundStyle(theme[head ? .fg : .fgMuted])
        .padding(.horizontal, metrics.size(9)).padding(.vertical, metrics.size(7))
        .background(head ? theme[.bgSunken] : Color.clear)
        .overlay(alignment: .top) { if !head { theme[.border].frame(height: metrics.size(1)) } }
    }

    private struct Bucket { let label: String; let value: Double; let share: Double }

    func dominant(_ sample: ResourceMonitor.Sample?) -> Bucket? {
        guard let sample, sample.totalMB > 0 else { return nil }
        return [Bucket(label: String(localized: "memModal.bucketApp"), value: sample.appMB, share: sample.appMB / sample.totalMB),
                Bucket(label: String(localized: "memModal.bucketPtys"), value: sample.terminalsMB,
                    share: sample.terminalsMB / sample.totalMB)]
            .max { $0.value < $1.value }
    }

    var diagnostics: [String] {
        guard let latest else { return [String(localized: "memModal.noData")] }
        var items: [String] = []
        if case .critical = level {
            items.append(String(localized: "memModal.diag.systemCritical"))
        } else if case .warning = level {
            items.append(String(localized: "memModal.diag.systemWarning"))
        } else if case .healthy = level {
        }
        if growth >= 512 { items.append(format("memModal.diag.highGrowth", mb(growth))) }
        else if growth >= 256 { items.append(format("memModal.diag.moderate", mb(growth))) }
        if let first = windowed.first, let last = windowed.last, windowed.count >= 2 {
            let buckets = [(String(localized: "memModal.bucketApp"), last.appMB - first.appMB),
                           (String(localized: "memModal.bucketPtys"), last.terminalsMB - first.terminalsMB)]
            if let top = buckets.max(by: { $0.1 < $1.1 }), top.1 >= 192 {
                items.append(format("memModal.diag.bucket", top.0, mb(top.1)))
            }
        }
        if let top = dominant(latest), top.share >= 0.6 {
            items.append(format("memModal.diag.dominant", top.label, String(format: "%.0f", top.share * 100)))
        }
        if latest.processCount >= 50 { items.append(format("memModal.diag.many", "\(latest.processCount)")) }
        return items.isEmpty ? [String(localized: "memModal.diag.stable")] : items
    }

    private var pressureLabel: String {
        if case .normal = environment.resources.pressure {
            String(localized: "memModal.pressure.normal")
        } else if case .warning = environment.resources.pressure {
            String(localized: "memModal.pressure.warning")
        } else {
            String(localized: "memModal.pressure.critical")
        }
    }

    private var pressureToken: ThemeToken {
        if case .normal = environment.resources.pressure {
            .fgMuted
        } else if case .warning = environment.resources.pressure {
            .statusWaiting
        } else {
            .statusOffline
        }
    }

    func mb(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        return String(format: abs(value) >= 100 ? "%.0f MB" : "%.1f MB", value)
    }

    func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }

    private func terminalName(_ tab: AletheModel.TabID) -> String {
        guard let (project, pane) = environment.workspace?.document.paneHolding(tab),
              let item = pane.tabs.first(where: { $0.id == tab }) else { return tab.rawValue }
        return "\(item.title ?? AgentLabels.name(for: item.agent)) · \(project.name)"
    }}
