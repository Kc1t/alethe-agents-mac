import AletheAgents
import AletheDesign
import AletheFoundation
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

struct OnboardingWebFeaturesStep: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @State private var term = ""
    @State private var expanded = false
    @FocusState private var searchFocused: Bool

    enum Group: CaseIterable { case workspace, agents, others }

    private func group(of feature: Feature) -> Group {
        if ({ if case .browser = feature { return true }; return false }()) ||
            ({ if case .prs = feature { return true }; return false }()) {
            .workspace
        } else if ({ if case .mcp = feature { return true }; return false }()) ||
            ({ if case .playwright = feature { return true }; return false }()) ||
            ({ if case .orchestrator = feature { return true }; return false }()) ||
            ({ if case .gsdSync = feature { return true }; return false }()) {
            .agents
        } else {
            .others
        }
    }

    private func icon(_ feature: Feature) -> String {
        if case .browser = feature {
            "macwindow"
        } else if case .mcp = feature {
            "powerplug"
        } else if case .playwright = feature {
            "cursorarrow.click.2"
        } else if case .orchestrator = feature {
            "point.3.connected.trianglepath.dotted"
        } else if case .graphify = feature {
            "point.3.filled.connected.trianglepath.dotted"
        } else if case .aiMemory = feature {
            "brain"
        } else if case .gsdSync = feature {
            "sparkles"
        } else {
            "arrow.triangle.pull"
        }
    }

    private func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    private func matches(_ feature: Feature, _ needle: String) -> Bool {
        needle.isEmpty || folded([
            String(localized: String.LocalizationValue("features.\(feature.rawValue).title")),
            String(localized: String.LocalizationValue("features.\(feature.rawValue).detail")),
            feature.rawValue,
        ].joined(separator: " ")).contains(needle)
    }

    private func isOn(_ feature: Feature) -> Bool { environment.features.isOn(feature) }

    private func toggle(_ feature: Feature) {
        let on = !isOn(feature)
        environment.preferences?.update { $0.features.set(feature, on: on) }
        if feature == .playwright, !on { Task { await environment.playwright.stop() } }
    }

    var body: some View {
        let needle = folded(term.trimmingCharacters(in: .whitespaces))
        let searching = !needle.isEmpty
        let visible = Feature.allCases.filter { matches($0, needle) }
        VStack(alignment: .leading, spacing: 0) {
            OnboardingWebIntro(title: "onboarding.web.featuresTitle", subtitle: Text("onboarding.web.featuresSubtitle"))
                .padding(.bottom, metrics.size(16))
            search
            ForEach(Group.allCases, id: \.self) { group in
                let rows = visible.filter { self.group(of: $0) == group }
                if !(group == .others && !searching && !expanded), !rows.isEmpty {
                    section(group, rows)
                }
            }
            if visible.isEmpty {
                Text("onboarding.web.featuresNoMatch")
                    .font(metrics.font(size: 12)).foregroundStyle(theme[.fgFaint])
                    .frame(maxWidth: .infinity).padding(.vertical, metrics.size(26))
            }
            if !searching, !expanded {
                OnboardingHover { hovering in
                    Button { expanded = true } label: {
                        HStack(spacing: metrics.size(9)) {
                            Text(verbatim: format("onboarding.web.featuresShowMore", Feature.allCases.filter(\.isSecondary).count))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down").font(metrics.font(size: 13))
                        }
                        .font(metrics.font(size: 11.5)).foregroundStyle(theme[hovering ? .fg : .fgFaint])
                        .padding(.top, metrics.size(9))
                        .overlay(alignment: .top) { Rectangle().fill(theme[.border]).frame(height: metrics.size(1)) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .accessibilityIdentifier("onboarding.features.more")
            }
        }
    }

    private var search: some View {
        HStack(spacing: metrics.size(9)) {
            Image(systemName: "magnifyingglass").font(metrics.font(size: 14))
            TextField(text: $term, prompt: Text("onboarding.web.featuresSearch")
                .foregroundStyle(theme[.fgFaint])) { Text("onboarding.web.featuresSearch") }
                .textFieldStyle(.plain)
                .font(metrics.font(size: 12.5)).foregroundStyle(theme[.fg])
                .focused($searchFocused)
                .accessibilityIdentifier("onboarding.features.search")
            if !term.isEmpty {
                Button { term = "" } label: { Image(systemName: "xmark").font(metrics.font(size: 12)) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("onboarding.web.featuresClearSearch"))
            }
        }
        .foregroundStyle(theme[.fgFaint])
        .padding(.horizontal, metrics.size(11))
        .frame(height: metrics.size(30))
        .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
            .strokeBorder(theme[searchFocused ? .accentBorder : .border], lineWidth: metrics.size(1)))
        .padding(.bottom, metrics.size(20))
    }

    private func section(_ group: Group, _ rows: [Feature]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group == .workspace ? "onboarding.web.featuresGroupWorkspace"
                 : group == .agents ? "onboarding.web.featuresGroupAgents" : "onboarding.web.featuresGroupOthers")
                .textCase(.uppercase)
                .font(metrics.font(size: 10, weight: .bold)).tracking(metrics.size(1))
                .foregroundStyle(theme[.fgFaint])
                .padding(.bottom, metrics.size(8))
            ForEach(Array(rows.enumerated()), id: \.element) { index, feature in
                row(feature, first: index == 0)
                if feature == .playwright, isOn(.playwright) { playwrightMode }
            }
        }
        .padding(.bottom, metrics.size(20))
    }

    private func row(_ feature: Feature, first: Bool) -> some View {
        let on = isOn(feature)
        return Button { toggle(feature) } label: {
            HStack(spacing: metrics.size(12)) {
                Image(systemName: icon(feature)).font(metrics.font(size: 15))
                    .foregroundStyle(theme[on ? .fg : .fgMuted])
                    .frame(width: metrics.size(28), height: metrics.size(28))
                    .background(theme[.surfaceCardDefault], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
                    .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                        .strokeBorder(theme[on ? .borderStrong : .border], lineWidth: metrics.size(1)))
                VStack(alignment: .leading, spacing: metrics.size(3)) {
                    HStack(spacing: metrics.size(7)) {
                        Text(feature.title).font(metrics.font(size: 12.5))
                        if feature == .orchestrator {
                            Text("onboarding.web.featuresExperimental")
                                .font(metrics.font(size: 9.5)).foregroundStyle(theme[.statusWaiting])
                                .padding(.horizontal, metrics.size(6)).padding(.vertical, metrics.size(1))
                                .overlay(Capsule().strokeBorder(theme[.statusWaiting], lineWidth: metrics.size(1)))
                        }
                    }
                    Text(feature.detail).font(metrics.font(size: 11)).foregroundStyle(theme[.fgFaint])
                        .lineSpacing(metrics.size(2)).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                track(on)
            }
            .foregroundStyle(theme[.fg])
            .padding(.vertical, metrics.size(10))
            .overlay(alignment: .top) {
                if !first { Rectangle().fill(theme[.border]).frame(height: metrics.size(1)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("settings.feature.\(feature.rawValue)")
    }

    private func track(_ on: Bool) -> some View {
        Capsule()
            .fill(theme[on ? .accentSoft : .bgSunken])
            .frame(width: metrics.size(32), height: metrics.size(19))
            .overlay(Capsule().strokeBorder(theme[on ? .accentBorder : .borderStrong], lineWidth: metrics.size(1)))
            .overlay(alignment: .leading) {
                Circle().fill(theme[on ? .accent : .fgFaint])
                    .frame(width: metrics.size(13), height: metrics.size(13))
                    .padding(.leading, metrics.size(on ? 15 : 2))
            }
            .animation(metrics.reducesMotion ? nil : .easeOut(duration: 0.12), value: on)
            .accessibilityHidden(true)
    }

    private var playwrightMode: some View {
        let mode = environment.preferences?.document.playwrightBrowserMode.flatMap(PlaywrightBrowserMode.init(rawValue:)) ?? .shared
        return HStack(spacing: metrics.size(12)) {
            Image(systemName: "macwindow").font(metrics.font(size: 13)).foregroundStyle(theme[.fgFaint])
                .frame(width: metrics.size(28))
            VStack(alignment: .leading, spacing: metrics.size(2)) {
                Text("settings.playwright.mode").font(metrics.font(size: 11.5)).foregroundStyle(theme[.fgMuted])
                Text(mode == .shared ? "settings.playwright.mode.shared.hint" : "settings.playwright.mode.dedicated.hint")
                    .font(metrics.font(size: 10.5)).foregroundStyle(theme[.fgFaint])
                    .lineSpacing(metrics.size(2)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: metrics.size(2)) {
                ForEach([PlaywrightBrowserMode.shared, .dedicated], id: \.self) { option in
                    Button {
                        environment.preferences?.update { $0.playwrightBrowserMode = option == .shared ? nil : option.rawValue }
                    } label: {
                        Text(option == .shared ? "settings.playwright.mode.shared" : "settings.playwright.mode.dedicated")
                            .font(metrics.font(size: 11))
                            .foregroundStyle(theme[mode == option ? .fg : .fgMuted])
                            .padding(.horizontal, metrics.size(9)).padding(.vertical, metrics.size(3))
                            .background(mode == option ? theme[.panelHover] : .clear,
                                        in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.playwright.\(option.rawValue)")
                }
            }
            .padding(metrics.size(2))
            .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
        }
        .padding(.vertical, metrics.size(8))
        .overlay(alignment: .top) {
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: 10_000, y: 0))
            }
            .stroke(theme[.border], style: StrokeStyle(lineWidth: metrics.size(1), dash: [metrics.size(3), metrics.size(3)]))
            .frame(height: metrics.size(1))
        }
    }
}
