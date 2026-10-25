import AletheFoundation
import Foundation

public struct PreferencesDocument: VersionedDocument, Hashable {
    public static let currentVersion = 2
    public static let migrations: [Int: @Sendable (inout JSONObject) throws -> Void] = [
        1: { migrateUsagePills(&$0) },
    ]
    public static let initial = PreferencesDocument()

    public static let defaultThemeID = "elite-indigo"
    public static let uiScaleRange: ClosedRange<Double> = 0.8...1.5
    public static let uiScaleStep = 0.1

    public var workspaceGridLayout: CustomGrid?
    public var workspaceGridLayoutHistory: [CustomGridHistoryEntry]?

    public var customAgents: [CustomAgentDefinition]?
    public var orchestratorShortcuts: [OrchestratorShortcut]?
    public var workerRuleSets: [WorkerRuleSet]?

    public var orchestration: OrchestrationPreferences?

    public var schemaVersion: Int
    public var displayName: String?
    public var profileImageUrl: String?
    public var windowOpacity: Double?
    public var topbarStyle: String?
    public var terminalTheme: String?
    public var spawnConcurrency: Int?
    public var shellPath: String?
    public var terminalFontFamily: String?
    public var themeID: String
    public var uiScale: Double
    public var alwaysStartUnrestricted: Bool
    public var enabledAgents: [String]?
    public var lastAgent: String?
    public var cliPaths: [String: String]?
    public var resourcePolicy: ResourcePolicy?
    public var startClean: Bool?
    public var confirmQuit: Bool?
    public var visualStyle: String?
    public var reducedMotion: Bool?
    public var lastTerminalCreation: TerminalCreation?
    public var notifyAgents: Bool?
    public var notifyLimitReset: Bool?
    public var startOnHome: Bool?
    public var setupDone: [String]?
    public var setupHidden: Bool?
    public var enabledFeatures: [String: Bool]?
    public var playwrightBrowserMode: String?
    public var playwrightDedicatedHeadless: Bool?
    public var playwrightSharedHeadless: Bool?
    public var playwrightBrowserPath: String?
    public var appIconTheme: String?
    public var gsdSyncModelChain: [String]?
    public var toolbarItems: [String: Bool]?
    public var graphifyCommand: String?
    public var onboardingDone: Bool?
    public var firstLaunchAt: Date?
    public var lastLaunchAt: Date?
    public var lastSeenVersion: String?
    public var mcpDefaultScope: String?
    public var mcpOnboardingSeen: Bool?
    public var spotifyClientID: String?
    public var discordPresence: Bool?
    public var router9: Router9Preferences?
    public var remote: RemotePreferences?

    public init(schemaVersion: Int = currentVersion, themeID: String = defaultThemeID, uiScale: Double = 1,
                alwaysStartUnrestricted: Bool = false, enabledAgents: [String]? = nil, lastAgent: String? = nil,
                cliPaths: [String: String]? = nil) {
        self.schemaVersion = schemaVersion
        self.themeID = themeID
        self.uiScale = uiScale
        self.alwaysStartUnrestricted = alwaysStartUnrestricted
        self.enabledAgents = enabledAgents
        self.lastAgent = lastAgent
        self.cliPaths = cliPaths
    }

    public var resources: ResourcePolicy { resourcePolicy ?? ResourcePolicy() }
    public var router9Settings: Router9Preferences { router9 ?? Router9Preferences() }
    public var remoteSettings: RemotePreferences { remote ?? RemotePreferences() }
    public var showsDiscordPresence: Bool { discordPresence ?? false }

    public mutating func zoom(by steps: Int) {
        let next = (uiScale + Double(steps) * Self.uiScaleStep) * 10
        uiScale = min(max(next.rounded() / 10, Self.uiScaleRange.lowerBound), Self.uiScaleRange.upperBound)
    }
}

public struct TerminalCreation: Codable, Hashable, Sendable {
    public var agent: String
    public var folder: String?
    public var unrestricted: Bool
    public var extraArguments: [String]
    public var useRouter9: Bool?

    public init(agent: String, folder: String? = nil, unrestricted: Bool = false, extraArguments: [String] = [],
                useRouter9: Bool? = nil) {
        self.agent = agent
        self.folder = folder
        self.unrestricted = unrestricted
        self.extraArguments = extraArguments
        self.useRouter9 = useRouter9
    }

    public func tab() -> PaneTab {
        var tab = PaneTab(agent: agent, workingDirectory: folder, unrestricted: unrestricted, extraArguments: extraArguments)
        tab.useRouter9 = useRouter9
        return tab
    }
}
