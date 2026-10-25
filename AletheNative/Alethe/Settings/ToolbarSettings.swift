import AletheDesign
import AletheModel
import SwiftUI

struct ToolbarSettings: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        SettingsPageForm {
            Section {
                ForEach(ToolbarItemKind.allCases, id: \.self) { item in
                    Toggle(item.title, isOn: Binding {
                        environment.preferences?.document.showsToolbarItem(item) ?? item.shownByDefault
                    } set: { shown in
                        environment.preferences?.update { $0.setToolbarItem(item, shown: shown) }
                    })
                    .accessibilityIdentifier("settings.toolbar.\(item.rawValue)")
                    .settingsRowSurface(.toolbar)
                }
            } footer: {
                Text("settings.toolbar.help")
            }
            Section {
                Button("settings.toolbar.restore") {
                    environment.preferences?.update { $0.toolbarItems = nil }
                }
                .disabled(environment.preferences?.document.toolbarItems == nil)
                .accessibilityIdentifier("settings.toolbar.restore")
            }
        }
        .formStyle(.grouped)
        .modifier(AletheSettingsSizing())
        .disabled(environment.preferences == nil)
        .accessibilityIdentifier("settings.toolbar")
    }
}

extension ToolbarItemKind {
    var title: LocalizedStringKey {
        if case .home = self {
            return "settings.toolbar.home"
        } else if case .usageClaude = self {
            return "settings.toolbar.usageClaude"
        } else if case .usageCodex = self {
            return "settings.toolbar.usageCodex"
        } else if case .usageAntigravity = self {
            return "settings.toolbar.usageAntigravity"
        } else if case .aiUsage = self {
            return "settings.toolbar.aiUsage"
        } else if case .notifications = self {
            return "settings.toolbar.notifications"
        } else if case .memory = self {
            return "settings.toolbar.memory"
        } else if case .profile = self {
            return "settings.toolbar.profile"
        } else if case .remote = self {
            return "settings.toolbar.remote"
        } else if case .router9 = self {
            return "settings.toolbar.router9"
        } else {
            return "settings.toolbar.sync"
        }
    }
}
