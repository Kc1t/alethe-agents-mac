import AletheDesign
import SwiftUI

struct IntegrationsSettings: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppEnvironment.self) private var environment
    @State private var showingUsage = false
    var body: some View {
        SettingsPageForm {
            if metrics.isWebInterface {
                Section {
                    Button("usage.title") { showingUsage = true }
                } header: { Text("settings.web.reference.prefs.usageAccess") }
                  footer: { Text("settings.web.reference.prefs.usageAccessDesc") }
                CommandLineToolSection()
                Router9SettingsSection()
                SpotifySettingsSection()
                DiscordSettingsSection()
                DictationSettingsSections(settings: environment.dictation.settings)
            } else {
                SpotifySettingsSection()
                DiscordSettingsSection()
                Router9SettingsSection()
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.integrations")
        .sheet(isPresented: $showingUsage) { AIUsageSheet() }
    }
}
