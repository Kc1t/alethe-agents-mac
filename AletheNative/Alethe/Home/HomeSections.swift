import AletheAgents
import AletheDesign
import AletheModel
import SwiftUI

struct UsageStrip: View {
    var homeActivityDays: Binding<[ActivityDays.Day]>?
    var webContainerWidth: CGFloat?
    @State private var activityDays: [ActivityDays.Day] = []
    @State var contentWidth: CGFloat = 0
    @Environment(AppEnvironment.self) var environment
    @Environment(\.theme) var theme
    @Environment(\.metrics) var metrics

    var body: some View {
        if metrics.isWebInterface { webBody } else { nativeBody }
    }

    var nativeBody: some View {
        VStack(alignment: .leading, spacing: metrics.space(.m)) {
            HStack {
                HomeSectionHeader(title: "home.usage")
                Spacer()
                Button {
                    Task { await environment.usage.refresh(UsageMonitor.providers) }
                } label: { Image(systemName: "arrow.clockwise").webProfileSized(14) }
                    .buttonStyle(.borderless)
                    .help(Text("home.refresh"))
                    .accessibilityLabel(Text("home.refresh"))
                Button("home.usage.details") { environment.editorRequest = .aiUsage }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("home.usage.details")
            }
            HStack(alignment: .top, spacing: metrics.space(.m)) {
                ForEach(UsageMonitor.providers, id: \.self) { provider in
                    card(provider).frame(maxWidth: .infinity)
                }
            }
        }
        .task { await environment.usage.refresh(environment.usage.shownProviders) }
    }

    var webBody: some View {
        VStack(alignment: .leading, spacing: metrics.size(12)) {
            HomeSectionHeader(title: "home.web.usageActivity").accessibilityIdentifier("home.usage.details")
            LazyVGrid(columns: webColumns, alignment: .leading, spacing: metrics.size(6)) {
                ForEach([AgentKind.claude, .codex], id: \.self) { webCard($0) }
                ActivityGraph(days: homeActivityDays ?? $activityDays)
            }
            .padding(metrics.size(6))
            .background(theme[.bgSunken].opacity(0.72), in: RoundedRectangle(cornerRadius: metrics.radius(.lg)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.lg))
                .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .task { await environment.usage.refresh(environment.usage.shownProviders) }
    }

    private var webColumns: [GridItem] {
        let paneWidth = webContainerWidth ?? contentWidth
        let gap = metrics.size(6)
        if paneWidth <= metrics.size(720) { return [GridItem(.flexible())] }
        if paneWidth <= metrics.size(1100) {
            return [GridItem(.flexible(), spacing: gap), GridItem(.flexible())]
        }
        let providerWidth = max(0, contentWidth - metrics.size(24)) / 3.15
        return [GridItem(.fixed(providerWidth), spacing: gap),
                GridItem(.fixed(providerWidth), spacing: gap), GridItem(.flexible())]
    }

    private func webCard(_ provider: AgentKind) -> some View {
        WebHomeUsageCard(provider: provider)
    }

    private func card(_ provider: AgentKind) -> some View {
        VStack(alignment: .leading, spacing: metrics.space(.s)) {
            Text(verbatim: AgentLabels.name(for: provider.rawValue)).font(metrics.font(.body).weight(.medium))
            if let usage = environment.usage.usage[provider], usage.status == .ready {
                ForEach(usage.windows.prefix(3)) { window in
                    HStack {
                        Text(verbatim: window.label).font(metrics.font(.footnote))
                        Spacer()
                        Text(verbatim: "\(Int(window.usedPercent.rounded()))%").font(metrics.font(.footnote).monospacedDigit())
                    }
                    ProgressView(value: min(window.usedPercent, 100), total: 100)
                        .tint(theme[UsageLevel.token(window.usedPercent)])
                    if let reset = window.resetsAt {
                        HStack(spacing: metrics.space(.xs)) {
                            Text("home.usage.resets")
                            Text(reset, format: .relative(presentation: .named))
                        }
                        .font(metrics.font(.caption))
                        .foregroundStyle(theme[.textTertiary])
                    }
                }
            } else if environment.usage.refreshing.contains(provider) {
                ProgressView().controlSize(.small)
            } else if let usage = environment.usage.usage[provider] {
                Text(usage.status == .noCLI ? "usage.noCLI" : usage.status == .noAuth ? "usage.noAuth" : "home.usage.unavailable")
                    .font(metrics.font(.footnote)).foregroundStyle(theme[.textTertiary])
            } else {
                Button("home.usage.check") { Task { await environment.usage.refresh([provider]) } }
                    .buttonStyle(.link)
                    .font(metrics.font(.footnote))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aletheCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.usage.\(provider.rawValue)")
    }
}

struct HomeWebCard: ViewModifier {
    @State var hovered = false
    @Environment(\.theme) var theme
    @Environment(\.metrics) var metrics

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, metrics.size(14)).padding(.vertical, metrics.size(13))
            .frame(maxWidth: .infinity, minHeight: metrics.size(244), maxHeight: .infinity, alignment: .topLeading)
            .background(theme[hovered ? .bgElevated : .bg].opacity(hovered ? 1 : 0.82),
                in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                .strokeBorder(theme[hovered ? .borderStrong : .borderSubtle], lineWidth: metrics.size(1)))
            .onHover { hovered = $0 }
            .animation(metrics.reducesMotion ? nil : Motion.animation(Motion.quick, reduceMotion: false), value: hovered)
    }
}
