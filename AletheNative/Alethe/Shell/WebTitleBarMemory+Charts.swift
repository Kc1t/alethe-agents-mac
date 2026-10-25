import AletheDesign
import AletheModel
import SwiftUI

extension WebTitleBarMemory {
    var historyPanel: some View {
        panel {
            panelHeader("memModal.history", subtitle: format("memModal.historySubtitle", "\(history.count)")) {
                if let latest {
                    Text(verbatim: time(latest.timestamp)).font(metrics.monoFont(size: 11))
                }
            }
            chart
        }
    }

    @ViewBuilder private var chart: some View {
        let samples = Array(history.suffix(90))
        if samples.count < 2 {
            Text("memModal.waitingMore").font(metrics.font(size: 12)).foregroundStyle(theme[.fgMuted])
                .frame(maxWidth: .infinity, minHeight: metrics.size(90))
        } else {
            let values = samples.map(\.totalMB)
            let low = values.min() ?? 0, high = values.max() ?? 0
            let range = max(high - low, 1)
            ZStack {
                GeometryReader { geometry in
                    let size = geometry.size
                    let points = samples.enumerated().map { index, sample in
                        CGPoint(x: CGFloat(index) / CGFloat(samples.count - 1) * size.width,
                                y: size.height - CGFloat((sample.totalMB - low) / range * 0.84 + 0.08) * size.height)
                    }
                    ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                        theme[.border].frame(height: metrics.size(1)).offset(y: size.height * fraction)
                    }
                    MemoryChartPath(points: points, closed: true)
                        .fill(theme[.accent].opacity(0.14))
                    MemoryChartPath(points: points, closed: false)
                        .stroke(theme[.accent], style: StrokeStyle(lineWidth: metrics.size(2), lineCap: .round, lineJoin: .round))
                    if let hoverIndex, points.indices.contains(hoverIndex) {
                        Path { path in
                            path.move(to: CGPoint(x: points[hoverIndex].x, y: size.height * 0.04))
                            path.addLine(to: CGPoint(x: points[hoverIndex].x, y: size.height * 0.96))
                        }
                        .stroke(theme[.borderStrong], style: StrokeStyle(lineWidth: metrics.size(1),
                            dash: [metrics.size(2), metrics.size(2)]))
                        Circle().fill(theme[.bgSunken])
                            .overlay(Circle().strokeBorder(theme[.accent], lineWidth: metrics.size(1.6)))
                            .frame(width: metrics.size(6), height: metrics.size(6))
                            .position(points[hoverIndex])
                    }
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { phase in
                            if case .active(let location) = phase {
                                let fraction = min(1, max(0, location.x / max(size.width, 1)))
                                hoverIndex = Int((fraction * CGFloat(samples.count - 1)).rounded())
                            } else if case .ended = phase {
                                hoverIndex = nil
                            }
                        }
                    if let hoverIndex, samples.indices.contains(hoverIndex), points.indices.contains(hoverIndex) {
                        let x = min(0.9, max(0.02, points[hoverIndex].x / max(size.width, 1))) * size.width
                        VStack(spacing: metrics.size(1)) {
                            Text(verbatim: mb(samples[hoverIndex].totalMB)).font(metrics.font(size: 12, weight: .semibold))
                                .foregroundStyle(theme[.fg])
                            Text(verbatim: time(samples[hoverIndex].timestamp)).font(metrics.monoFont(size: 10))
                                .foregroundStyle(theme[.fgMuted])
                        }
                        .padding(.horizontal, metrics.size(8)).padding(.vertical, metrics.size(4))
                        .background(theme[.surfaceModal], in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
                        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm)).strokeBorder(theme[.borderAccent],
                            lineWidth: metrics.size(1)))
                        .shadow(color: theme.shadow(.md).color.color, radius: metrics.size(8), y: metrics.size(4))
                        .fixedSize()
                        .position(x: x, y: metrics.size(8) + metrics.size(18))
                        .allowsHitTesting(false)
                    }
                }
                VStack {
                    Text(verbatim: mb(high)); Spacer(); Text(verbatim: mb(low))
                }
                .font(metrics.monoFont(size: 10)).foregroundStyle(theme[.fgMuted])
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.size(10)).padding(.vertical, metrics.size(8))
                .allowsHitTesting(false)
            }
            .frame(height: metrics.size(150))
            .background(theme[.bgSunken])
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius(.sm)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
            .accessibilityIdentifier("memory.chart")
        }
    }

    var bottlenecksPanel: some View {
        let top = dominant(latest)
        return panel {
            panelHeader("memModal.bottlenecks", subtitle: top.map { format("memModal.bottleneckLead", $0.label, mb($0.value)) }
                        ?? String(localized: "memModal.noReading")) {
                Image(systemName: "exclamationmark.triangle").font(metrics.font(size: 16))
            }
            VStack(spacing: metrics.size(6)) {
                ForEach(diagnostics, id: \.self) { item in
                    Text(verbatim: item).font(metrics.font(size: 12)).foregroundStyle(theme[.fg])
                        .lineSpacing(metrics.size(1.5))
                        .padding(.horizontal, metrics.size(10)).padding(.vertical, metrics.size(8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
                        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm)).strokeBorder(theme[.border],
                            lineWidth: metrics.size(1)))
                }
            }
        }
    }

    var compositionPanel: some View {
        panel {
            panelHeader("memModal.composition", subtitle: latest.map { format("memModal.processes", "\($0.processCount)") }
                        ?? String(localized: "memModal.waiting")) {
                Image(systemName: "terminal").font(metrics.font(size: 16))
            }
            if let latest, latest.totalMB > 0 {
                VStack(spacing: metrics.size(10)) {
                    bucketRow("memModal.bucketApp", latest.appMB, latest.totalMB)
                    bucketRow("memModal.bucketPtys", latest.terminalsMB, latest.totalMB)
                }
            }
        }
    }

    private func bucketRow(_ title: LocalizedStringKey, _ value: Double, _ total: Double) -> some View {
        VStack(spacing: metrics.size(5)) {
            HStack {
                Text(title).foregroundStyle(theme[.fgMuted])
                Spacer()
                Text(verbatim: mb(value)).font(metrics.monoFont(size: 11)).foregroundStyle(theme[.fg])
            }.font(metrics.font(size: 11))
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: metrics.size(4)).fill(theme[.accent])
                    .frame(width: geometry.size.width * CGFloat(max(0.02, value / total)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: metrics.size(7))
            .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.size(4)))
            .overlay(RoundedRectangle(cornerRadius: metrics.size(4)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
        }
    }
}
