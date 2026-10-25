import AletheAgents
import AletheDesign
import AletheFoundation
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

struct WelcomeBackSheet: View {
    let welcome: WelcomeBack
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var nativeDismiss
    @Environment(\.modalsM2Close) private var closeOverlay
    private func dismiss() {
        if let closeOverlay { closeOverlay() } else { nativeDismiss() }
    }
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    private var name: String { environment.activeProfileName }

    var body: some View {
        if metrics.isWebInterface { webBody } else { nativeBody }
    }

    private var webBody: some View {
        GitWebModal(close: dismiss) {
            Text(verbatim: format("welcome.day", welcome.day, AppIdentity.productName))
        } content: {
            VStack(spacing: metrics.size(14)) {
            Circle()
                .fill(theme[.accentSoft])
                .frame(width: metrics.size(56), height: metrics.size(56))
                .overlay {
                    Text(verbatim: name.first.map { String($0).uppercased() } ?? "?")
                        .font(metrics.font(.title1))
                        .foregroundStyle(theme[.accent])
                }
                .accessibilityHidden(true)
            Text(verbatim: format("welcome.day", welcome.day, AppIdentity.productName))
                .font(metrics.font(.footnote).weight(.semibold))
                .foregroundStyle(theme[.textSecondary])
            Text(verbatim: format("welcome.greeting", name))
                .font(metrics.font(.title1))
            Text(verbatim: subtitle)
                .foregroundStyle(theme[.textSecondary])
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("welcome.subtitle")
            }.frame(maxWidth: .infinity)
        } footer: {
            Spacer()
            Button("welcome.skip", action: dismiss)
            Button("welcome.start") { environment.showingHome = false; dismiss() }
                .buttonStyle(AletheButtonStyle(.primary))
                .keyboardShortcut(.defaultAction).accessibilityIdentifier("welcome.start")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome")
    }

    private var nativeBody: some View {
        VStack(spacing: metrics.space(.l)) {
            Circle()
                .fill(theme[.accentSoft])
                .frame(width: metrics.size(56), height: metrics.size(56))
                .overlay {
                    Text(verbatim: name.first.map { String($0).uppercased() } ?? "?")
                        .font(metrics.font(.title1))
                        .foregroundStyle(theme[.accent])
                }
                .accessibilityHidden(true)
            Text(verbatim: format("welcome.day", welcome.day, AppIdentity.productName))
                .font(metrics.font(.footnote).weight(.semibold))
                .foregroundStyle(theme[.textSecondary])
            Text(verbatim: format("welcome.greeting", name))
                .font(metrics.font(.title1))
            Text(verbatim: subtitle)
                .foregroundStyle(theme[.textSecondary])
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("welcome.subtitle")
            HStack(spacing: metrics.space(.m)) {
                Button("welcome.skip") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("welcome.start") {
                    environment.showingHome = false
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("welcome.start")
            }
            .padding(.top, metrics.space(.s))
        }
        .padding(metrics.space(.huge))
        .frame(width: metrics.size(420))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome")
    }

    private var subtitle: String {
        if let from = welcome.updatedFrom {
            return format("welcome.updated", AppEnvironment.appVersion, from)
        }
        return String(localized: "welcome.subtitle")
    }
}

extension AppEnvironment {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var mcpStore: McpStore? {
        guard let locations, let profileID else { return nil }
        var home = McpHome.current()
        #if DEBUG
        if UserDefaults.standard.string(forKey: "AletheIntegrationsHome") != nil {
            home = McpHome(home: Self.integrationsHome)
        }
        #endif
        return McpStore(home: home, writer: ConfigFileWriter(profileDirectory: locations.profileDirectory(profileID)))
    }

    func greetLaunch() {
        guard let preferences, let workspace else { return }
        var greeting = LaunchGreeting.none
        let hasProjects = !workspace.document.projects.isEmpty
        preferences.update { greeting = $0.recordLaunch(version: Self.appVersion, hasProjects: hasProjects) }
        guard editorRequest == nil else { return }
        if case .onboarding = greeting, Self.greets("AletheUITestOnboarding") {
            editorRequest = .onboarding
        } else if case .welcomeBack(let welcome) = greeting, Self.greets("AletheUITestWelcome") {
            editorRequest = .welcome(welcome)
        } else {
        }
    }

    private static func greets(_ testFlag: String) -> Bool {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "AletheDataRoot") != nil {
            return UserDefaults.standard.bool(forKey: testFlag)
        }
        #endif
        return true
    }
}
