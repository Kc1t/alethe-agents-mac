import AletheAgents
import AletheDesign
import AletheFoundation
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

struct OnboardingHover<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State var hovering = false

    var body: some View {
        content(hovering).onHover { hovering = $0 }
    }
}

struct OnboardingWebOverlay<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.metrics) var metrics
    @Environment(\.theme) var theme
    @State var visible = false

    var body: some View {
        GeometryReader { geometry in
            let maximumHeight = max(0, geometry.size.height - metrics.size(48))
            ZStack {
                Color.black.opacity(0.55)
                    .webModalBackdropMotion(visible: visible)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                content()
                    .environment(\.newTerminalModalHeight, maximumHeight)
                    .frame(width: min(metrics.size(640), max(0, geometry.size.width - metrics.size(48))))
                    .frame(maxHeight: maximumHeight)
                    .shadow(color: theme.shadow(.lg).color.color, radius: metrics.size(40), y: metrics.size(16))
                    .webModalContentMotion(visible: visible)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear { visible = true }
        .accessibilityAddTraits(.isModal)
    }
}

struct OnboardingWebButtonStyle: ButtonStyle {
    enum Kind { case normal, ghost, primary }
    var kind: Kind = .normal

    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, kind: kind)
    }

    private struct ButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @Environment(\.metrics) var metrics
        @Environment(\.theme) var theme
        @Environment(\.isEnabled) var enabled
        @State var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: metrics.radius(.md))
            configuration.label
                .font(metrics.font(size: 12.5, weight: kind == .primary ? .medium : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, metrics.size(13))
                .frame(height: metrics.size(30))
                .background(background, in: shape)
                .overlay(shape.strokeBorder(border, lineWidth: metrics.size(1)))
                .contentShape(shape)
                .opacity(enabled ? 1 : 0.5)
                .onHover { hovering = $0 && enabled }
        }

        private var foreground: Color {
            if case .normal = kind {
                theme[.fg]
            } else if case .ghost = kind {
                theme[hovering ? .fg : .fgMuted]
            } else {
                theme[.accentOn]
            }
        }

        var background: Color {
            if case .normal = kind {
                theme[.surfaceCardDefault]
            } else if case .ghost = kind {
                .clear
            } else {
                theme[hovering ? .accentStrong : .accent]
            }
        }

        var border: Color {
            if case .normal = kind {
                theme[.border]
            } else if case .ghost = kind {
                .clear
            } else {
                theme[.accent]
            }
        }
    }
}

struct OnboardingWebHeader: View {
    let count: Int
    let current: Int
    let progressLabel: String
    @Environment(AppEnvironment.self) var environment
    @Environment(\.metrics) var metrics
    @Environment(\.theme) var theme
    @State private var language = LanguageSetting().current()

    var body: some View {
        HStack(spacing: metrics.size(10)) {
            Group {
                if let icon = AppIcon.image(for: environment.preferences?.document.iconTheme ?? .default) {
                    Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app")
                }
            }
            .frame(width: metrics.size(22), height: metrics.size(22))
            .accessibilityHidden(true)
            Text("onboarding.kicker")
                .textCase(.uppercase)
                .font(metrics.font(size: 10, weight: .bold))
                .tracking(metrics.size(0.9))
                .foregroundStyle(theme[.fgFaint])
            Spacer(minLength: 0)
            HStack(spacing: metrics.size(4)) {
                ForEach(0..<count, id: \.self) { position in
                    Capsule()
                        .fill(theme[position <= current ? .accent : .borderStrong])
                        .frame(width: metrics.size(17), height: metrics.size(3))
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: progressLabel))
            .accessibilityIdentifier("onboarding.progress")
            HStack(spacing: metrics.size(2)) {
                ForEach([AppLanguage.english, .portugueseBrazil], id: \.self) { option in
                    Button { language = option; LanguageSetting().set(option) } label: {
                        Text(verbatim: String(option.rawValue.prefix(2)).uppercased())
                            .font(metrics.font(size: 10.5))
                            .foregroundStyle(theme[language == option ? .fg : .fgFaint])
                            .padding(.horizontal, metrics.size(6)).padding(.vertical, metrics.size(2))
                            .background(language == option ? theme[.surfaceCardDefault] : .clear,
                                        in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.language.\(option.rawValue)")
                }
            }
        }
        .padding(.horizontal, metrics.size(18)).padding(.vertical, metrics.size(12))
        .background(theme[.bgSunken])
        .overlay(alignment: .bottom) { Rectangle().fill(theme[.border]).frame(height: metrics.size(1)) }
    }
}

struct OnboardingWebIntro: View {
    let title: LocalizedStringKey
    let subtitle: Text
    @Environment(\.metrics) var metrics
    @Environment(\.theme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.size(5)) {
            Text(title).font(metrics.font(size: 18, weight: .semibold)).tracking(metrics.size(-0.27))
            subtitle.font(metrics.font(size: 12.5)).foregroundStyle(theme[.fgMuted])
                .lineSpacing(metrics.size(4)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
