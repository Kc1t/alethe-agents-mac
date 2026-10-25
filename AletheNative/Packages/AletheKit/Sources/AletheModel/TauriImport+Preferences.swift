import AletheFoundation
import Foundation

extension TauriImport {
    static func importPreferences(_ file: File, into preferences: inout PreferencesDocument, context: Context,
                                          report: inout Report) {
        let raw = file.preferences
        func portable<T: Decodable>(_ key: String, as type: T.Type) -> T? {
            guard let value = raw[key], !(value is NSNull), JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        if raw["orchestration"] != nil { preferences.orchestration = portable("orchestration", as: OrchestrationPreferences.self) }
        if raw["workerRuleSets"] != nil { preferences.workerRuleSets = portable("workerRuleSets", as: [WorkerRuleSet].self) }
        if raw["orchestratorShortcuts"] != nil { preferences.orchestratorShortcuts = portable("orchestratorShortcuts",
            as: [OrchestratorShortcut].self) }
        if raw["customAgents"] != nil { preferences.customAgents = portable("customAgents", as: [CustomAgentDefinition].self) }
        importBasicPreferences(file, into: &preferences, context: context, report: &report)
    }

    private static func importBasicPreferences(_ file: File, into preferences: inout PreferencesDocument,
                                                context: Context, report: inout Report) {
        let raw = file.preferences
        if let theme = raw["uiTheme"] as? String, context.themes.contains(theme), theme != preferences.themeID {
            preferences.themeID = theme
            report.preferences.insert(.theme)
        }
        if let zoom = raw["uiZoom"] as? Double {
            let range = PreferencesDocument.uiScaleRange
            let scale = min(max((zoom * 10).rounded() / 10, range.lowerBound), range.upperBound)
            if scale != preferences.uiScale {
                preferences.uiScale = scale
                report.preferences.insert(.interfaceSize)
            }
        }
        if let enabled = raw["enabledAgents"] as? [String: Any] {
            let known = context.agents.union((preferences.customAgents ?? []).map(\.id))
            let kinds = known.sorted().filter { (enabled[$0] as? Bool) ?? true }
            let value: [String]? = kinds.count == known.count ? nil : kinds
            if value != preferences.enabledAgents {
                preferences.enabledAgents = value
                report.preferences.insert(.enabledAgents)
            }
        }
        if let unrestricted = raw["alwaysStartUnrestricted"] as? Bool, unrestricted != preferences.alwaysStartUnrestricted {
            preferences.alwaysStartUnrestricted = unrestricted
            report.preferences.insert(.alwaysUnrestricted)
        }
        var paths = preferences.cliPaths ?? [:]
        for (agent, value) in file.cliPaths {
            guard context.agents.contains(agent), let path = value as? String, isAbsolute(path),
                  context.fileExists(path), paths[agent] != path else { continue }
            paths[agent] = path
            report.preferences.insert(.cliPaths)
        }
        if report.preferences.contains(.cliPaths) { preferences.cliPaths = paths }
        importFeaturePreferences(raw, into: &preferences, report: &report)
    }

    private static func importFeaturePreferences(_ raw: [String: Any], into preferences: inout PreferencesDocument,
                                                  report: inout Report) {
        if let stored = raw["enabledFeatures"] as? [String: Any] {
            var features = preferences.features
            for feature in Feature.allCases {
                if let on = stored[feature.rawValue] as? Bool { features.set(feature, on: on) }
            }
            if features.enabled != preferences.features.enabled {
                preferences.features = features
                report.preferences.insert(.features)
            }
        }
        if let icon = (raw["appIconTheme"] as? String).flatMap(AppIconTheme.init(rawValue:)), icon != preferences.iconTheme {
            preferences.iconTheme = icon
            report.preferences.insert(.appIcon)
        }
        let toolbar: [(String, ToolbarItemKind)] = [
            ("topbarShowClaudeUsage", .usageClaude), ("topbarShowCodexUsage", .usageCodex),
            ("topbarShowAntigravityUsage", .usageAntigravity), ("topbarShowProfile", .profile),
            ("topbarShowMemory", .memory), ("topbarShowSync", .sync), ("topbarShowRouter9", .router9),
        ]
        for (key, item) in toolbar {
            if let shown = raw[key] as? Bool, shown != preferences.showsToolbarItem(item) {
                preferences.setToolbarItem(item, shown: shown)
                report.preferences.insert(.toolbar)
            }
        }
        if let scope = raw["mcpDefaultScope"] as? String, scope == "project" || scope == "global",
           scope != preferences.mcpDefaultScope ?? "global" {
            preferences.mcpDefaultScope = scope
            report.preferences.insert(.mcp)
        }
        if raw["mcpOnboardingSeen"] as? Bool == true, preferences.mcpOnboardingSeen != true {
            preferences.mcpOnboardingSeen = true
            report.preferences.insert(.mcp)
        }
        importPeripherals(raw, into: &preferences, report: &report)
        if let language = raw["language"] as? String, !language.isEmpty { report.language = language }
    }

    private static func importPeripherals(_ raw: [String: Any], into preferences: inout PreferencesDocument,
                                          report: inout Report) {
        if let id = (raw["spotifyClientId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           id != preferences.spotifyClientID {
            preferences.spotifyClientID = id
            report.preferences.insert(.integrations)
        }
        if let on = raw["discordRichPresenceEnabled"] as? Bool, on != preferences.showsDiscordPresence {
            preferences.discordPresence = on
            report.preferences.insert(.integrations)
        }
        if let stored = raw["router9"] as? [String: Any] {
            var router9 = preferences.router9Settings
            if let value = stored["enabled"] as? Bool { router9.enabled = value }
            if let value = stored["autoStart"] as? Bool { router9.autoStart = value }
            if let value = stored["source"] as? String { router9.source = value == "external" ? .external : .managed }
            if let value = stored["port"] as? Int { router9.port = value }
            if let value = stored["defaultForNewAgents"] as? Bool { router9.defaultForNewAgents = value }
            if router9 != preferences.router9Settings {
                preferences.router9 = router9
                report.preferences.insert(.router9)
            }
        }
        var remote = preferences.remoteSettings
        if let value = raw["remoteMaxDevices"] as? Int { remote.maxDevices = value }
        if let value = raw["remoteSessionExpirySecs"] as? Int { remote.sessionExpirySecs = value }
        if let value = raw["remoteReadOnly"] as? Bool { remote.readOnly = value }
        if let value = raw["remoteAllowShellInput"] as? Bool { remote.allowShellInput = value }
        if let value = raw["remoteUseTailscale"] as? Bool { remote.useTailscale = value }
        if remote != preferences.remoteSettings {
            preferences.remote = remote
            report.preferences.insert(.remote)
        }
    }

}
