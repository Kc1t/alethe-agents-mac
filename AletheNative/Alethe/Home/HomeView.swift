import AletheAgents
import AletheDesign
import AletheModel
import AppKit
import SwiftUI

struct HomeView: View {
    let workspace: WorkspaceModel
    @Environment(AppEnvironment.self) var environment
    @Environment(\.theme) var theme
    @Environment(\.metrics) var metrics
    @State private var appeared = false
    @State private var activityDays: [ActivityDays.Day] = []

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.size(24)) {
                if metrics.isWebInterface {
                    VStack(spacing: metrics.size(18)) {
                        HomeHero(
                            streak: ActivityDays.streak(activityDays),
                            availableWidth: min(metrics.size(940), geometry.size.width - 2 * min(
                                metrics.size(28), max(metrics.size(16), geometry.size.width * 0.03)))
                                - (geometry.size.width - 2 * min(metrics.size(28), max(metrics.size(16),
                                    geometry.size.width * 0.03)) <= metrics.size(620) ? 0 : metrics.size(36)))
                        QuickLaunch(workspace: workspace, compactToolbar: geometry.size.width
                                    - 2 * min(metrics.size(28), max(metrics.size(16), geometry.size.width * 0.03))
                                    <= metrics.size(620))
                        HStack(spacing: metrics.size(8)) {
                            Button { environment.editorRequest = .newTerminal(nil) } label: {
                                Label { Text(metrics.isWebInterface ? "home.web.newTerminal" :
                                    "home.action.newTerminal") } icon: { Image(systemName: "terminal").webProfileSized(14) }
                            }
                            Button { environment.editorRequest = .newProject(.ungrouped) } label: {
                                Label { Text(metrics.isWebInterface ? "home.web.newProject" :
                                    "home.action.newProject") } icon: { Image(systemName: "folder.badge.plus").webProfileSized(14) }
                            }
                        }
                        .buttonStyle(HomeHeroActionStyle())
                    }
                    .padding(.horizontal, geometry.size.width - 2 * min(metrics.size(28), max(metrics.size(16),
                        geometry.size.width * 0.03)) <= metrics.size(620) ? 0 : metrics.size(18))
                    .padding(.top, metrics.size(28))
                    .padding(.bottom, metrics.size(42))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.width - 2 * min(metrics.size(28), max(metrics.size(16),
                        geometry.size.width * 0.03)) <= metrics.size(900)
                           ? metrics.size(430)
                           : min(metrics.size(610), max(metrics.size(430), geometry.size.height * 0.56)))
                    .entrance(appeared, step: 0, reduced: metrics.reducesMotion || (metrics.isWebInterface &&
                        metrics.style == .clean), rise: metrics.size(8))
                    WebHomeSetup(workspace: workspace)
                } else {
                    VStack(alignment: .leading, spacing: metrics.space(.xxl)) {
                        Spacer(minLength: metrics.size(28))
                        HomeHero(streak: ActivityDays.streak(activityDays))
                            .frame(maxWidth: .infinity)
                        QuickLaunch(workspace: workspace)
                            .frame(maxWidth: .infinity)
                        HStack(spacing: metrics.space(.xl)) {
                            Button { environment.editorRequest = .newTerminal(nil) } label: {
                                Label { Text(metrics.isWebInterface ? "home.web.newTerminal" :
                                    "home.action.newTerminal") } icon: { Image(systemName: "terminal").webProfileSized(14) }
                            }
                            Button { environment.editorRequest = .newProject(.ungrouped) } label: {
                                Label { Text(metrics.isWebInterface ? "home.web.newProject" :
                                    "home.action.newProject") } icon: { Image(systemName: "folder.badge.plus").webProfileSized(14) }
                            }
                        }
                        .buttonStyle(.link)
                        .font(metrics.font(.footnote))
                        .frame(maxWidth: .infinity)
                        Spacer(minLength: metrics.size(42))
                        SetupWalkthroughView(workspace: workspace)
                    }
                    .frame(minHeight: metrics.size(430))
                    .entrance(appeared, step: 0, reduced: metrics.reducesMotion, rise: metrics.size(8))
                }
                (metrics.isWebInterface
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: metrics.size(20)))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: metrics.space(.xxl)))) {
                    if metrics.isWebInterface {
                        WebHomeOverview(workspace: workspace)
                    } else {
                        RecentProjects(workspace: workspace)
                        HomeActions().frame(width: metrics.size(240))
                    }
                }
                .entrance(appeared, step: 1, reduced: metrics.reducesMotion || (metrics.isWebInterface &&
                    metrics.style == .clean), rise: metrics.size(8))
                VStack(alignment: .leading, spacing: metrics.size(24)) {
                    if metrics.isWebInterface {
                        UsageStrip(homeActivityDays: $activityDays, webContainerWidth: geometry.size.width
                                   - 2 * min(metrics.size(28), max(metrics.size(16), geometry.size.width * 0.03)))
                    }
                    else {
                        UsageStrip()
                        ActivityGraph(days: $activityDays)
                    }
                    TimeAnalytics()
                    if metrics.isWebInterface { HomeWebNotifications() }
                    else {
                        NotificationList(isHome: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .aletheCard()
                    }
                    HomeFooter()
                }
                .entrance(appeared, step: 2, reduced: metrics.reducesMotion || (metrics.isWebInterface &&
                    metrics.style == .clean), rise: metrics.size(8))
            }
            .frame(maxWidth: metrics.size(940), alignment: .leading)
            .padding(.horizontal, metrics.isWebInterface
                     ? min(metrics.size(28), max(metrics.size(16), geometry.size.width * 0.03))
                     : metrics.size(28))
            .padding(.bottom, metrics.size(18))
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                if metrics.isWebInterface {
                    HomeBackdrop()
                        .frame(height: geometry.size.width - 2 * min(metrics.size(28), max(metrics.size(16),
                            geometry.size.width * 0.03)) <= metrics.size(900)
                               ? metrics.size(620)
                               : min(metrics.size(780), max(metrics.size(560), geometry.size.height * 0.72)))
                }
            }
        }
        .background(theme[.bg])
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home")
        }
    }
}

extension View {
    func entrance(_ appeared: Bool, step: Int, reduced: Bool, rise: CGFloat) -> some View {
        opacity(appeared || reduced ? 1 : 0)
            .offset(y: appeared || reduced ? 0 : rise)
            .animation(reduced ? nil : .easeOut(duration: 0.28).delay(Double(step) * 0.06), value: appeared)
    }

}

struct HomeSectionHeader: View {
    let title: LocalizedStringKey
    var count: Int?
    @Environment(\.theme) var theme
    @Environment(\.metrics) var metrics

    var body: some View {
        HStack(spacing: metrics.size(metrics.isWebInterface ? 10 : 6)) {
            if metrics.isWebInterface {
                Text(title).textCase(.uppercase)
                    .font(metrics.font(size: 11, weight: .medium))
                    .tracking(metrics.size(1.4)).foregroundStyle(theme[.textTertiary])
                if let count {
                    Text(verbatim: "\(count)").font(metrics.monoFont(size: 10))
                        .foregroundStyle(theme[.textTertiary])
                        .padding(.horizontal, metrics.size(6)).padding(.vertical, metrics.size(1))
                        .background(theme[.bgElevated], in: Capsule())
                        .overlay(Capsule().strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                }
            } else {
                AletheSectionLabel(Text(title), tracking: 1.4, color: .textTertiary)
                if let count { AletheCountPill(count, monospaced: true) }
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

enum HomeFormat {
    static func duration(ms: UInt64) -> String {
        let minutes = Int((Double(ms) / 60_000).rounded())
        let units: Set<Duration.UnitsFormatStyle.Unit> = minutes < 60 ? [.minutes] : [.hours, .minutes]
        return Duration.seconds(minutes * 60).formatted(.units(allowed: units, width: .narrow))
    }
}

