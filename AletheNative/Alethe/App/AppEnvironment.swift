import AletheAgents
import AletheDesign
import AletheFoundation
import AletheGitControl
import AletheIntegrations
import AletheModel
import AlethePluginKit
import AletheTodos
import AletheTerminal
import AletheThemePack
import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppEnvironment {
    private(set) var profiles: DocumentModel<ProfileIndexDocument>?
    private(set) var workspace: WorkspaceModel?
    private(set) var preferences: PreferencesModel?
    private(set) var promptHistory: PromptHistoryModel?
    private(set) var pullRequestReviews: PullRequestReviewsModel?
    private(set) var locations: DataLocations?
    private(set) var profileID: ProfileID?
    var relaunching = false
    var dataMaintenanceResult: Result<PendingDataOperation?, any Error> = .success(nil)
    private(set) var plugins: PluginHost?
    private(set) var extensions: ExtensionManager?
    var editorRequest: EditorRequest?
    var focusModePaneID: PaneID?
    var inspectedPaneID: PaneID?
    var showingHome = false
    var settingsTab = SettingsTab.general
    var rightSidebarVisible = UserDefaults.standard.bool(forKey: "main.rightSidebarVisible") {
        didSet { UserDefaults.standard.set(rightSidebarVisible, forKey: "main.rightSidebarVisible") }
    }
    var rightSidebarTab: String?
    var newTodoRequest = 0
    @ObservationIgnored private var pendingFolders: [URL] = []

    let launchers = LauncherCache()
    let terminals = TerminalRegistry()
    let resources = ResourceMonitor()
    let installer = AgentInstaller()
    let notifier = AgentNotifier()
    let usage = UsageMonitor()
    let activity = ActivityTracker()
    let dictation = DictationController()
    let diagnostics = DiagnosticsController()
    let aiMemory = AiMemoryController()
    let graphify = GraphifyController()
    let playwright = PlaywrightBrowser()
    let gsdSync = GSDSyncController()
    let multiagent = MultiagentController()
    let orchestrator = OrchestratorService()
    let remoteControl = RemoteControlController()
    let discordPresence = DiscordPresenceController()
    let nowPlaying = NowPlayingController()
    let gistSync = GistSyncController()
    let router9 = Router9Controller()
    let contentPanes = ContentPaneRegistry()
    let launchLanguage = LanguageSetting().current()

    var dictationLocale: Locale {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let code = Locale.Language(identifier: language).languageCode?.identifier ?? "en"
        return Locale(languageCode: .init(code), languageRegion: Locale.current.region)
    }

    var isLoaded: Bool { workspace != nil && preferences != nil }

    var themeCatalog: ThemeCatalog {
        guard let plugins, !plugins.contributions.themes.isEmpty else { return .builtin }
        let contributed = plugins.contributions.themes
        if let cache = themeCatalogCache, cache.contributions == contributed { return cache.catalog }
        let catalog = ThemeCatalog.builtin.merging(contributions: contributed)
        themeCatalogCache = (contributed, catalog)
        return catalog
    }

    @ObservationIgnored private var themeCatalogCache: (contributions: [ThemeContribution], catalog: ThemeCatalog)?

    var theme: Theme {
        themeCatalog.resolved(id: preferences?.document.themeID ?? PreferencesDocument.defaultThemeID)
            .styled(visualStyle)
    }

    var visualStyle: VisualStyle {
        preferences?.document.visualStyle.flatMap(VisualStyle.init(rawValue:)) ?? .normal
    }

    var interfaceStyle: InterfaceStyle = UserDefaults.standard.string(forKey: "interfaceStyle")
        .flatMap(InterfaceStyle.init(rawValue:)) ?? .web {
        didSet { UserDefaults.standard.set(interfaceStyle.rawValue, forKey: "interfaceStyle") }
    }

    private(set) var systemReducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var reducesMotion: Bool { preferences?.document.reducedMotion == true || systemReducesMotion }

    var terminalFontSize: Float {
        TerminalAppearance.defaultFontSize * Float(preferences?.document.uiScale ?? 1)
    }

    var metrics: Metrics {
        Metrics(scale: CGFloat(preferences?.document.uiScale ?? 1), style: visualStyle, interface: interfaceStyle,
                reducesMotion: reducesMotion)
    }

    var features: Features { preferences?.document.features ?? .defaults }

    var skillStore: SkillStore { SkillStore(home: Self.integrationsHome) }

    private(set) var mcp: McpManagerModel?

    static var mcpHome: McpHome {
        integrationsHomeOverridden ? McpHome(home: integrationsHome) : .current()
    }

    static var integrationsHomeOverridden: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "AletheIntegrationsHome") != nil
        #else
        return false
        #endif
    }

    static var integrationsHome: URL {
        #if DEBUG
        if let home = UserDefaults.standard.string(forKey: "AletheIntegrationsHome") {
            return URL(filePath: home, directoryHint: .isDirectory)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    var agentLauncher: AgentLauncher {
        AgentLauncher(registry: agentRegistry, launchers: launchers, overrides: preferences?.document.cliPaths ?? [:])
    }

    #if DEBUG
    var loadingSampleData = false
    #endif

    private(set) var startupFinished = false

    @ObservationIgnored private var startupTask: Task<Void, Never>?

    func load() async {
        if let startupTask { await startupTask.value; return }
        let task = Task { await loadOnce() }
        startupTask = task
        await task.value
    }

    private func loadOnce() async {
        defer { startupFinished = true }
        guard !isLoaded, let locations = try? Self.dataLocations() else { return }
        self.locations = locations
        dataMaintenanceResult = await Task.detached { () -> Result<PendingDataOperation?, any Error> in
            Result { try DataMaintenance.applyPending(in: locations) }
        }.value
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "AletheUITestCrashMarker") {
            SessionMarkerStore(logsDirectory: locations.logs).begin(
                SessionMarker(startedAt: .now.addingTimeInterval(-60), appVersion: "0.0-test", build: "0", processID: 1))
        }
        #endif
        await diagnostics.start(logs: locations.logs)
        await multiagent.start(logs: locations.logs)
        let profiles = await DocumentModel<ProfileIndexDocument>.load(from: locations.profileIndex)
        let profile = profiles.document.activeProfile.id
        profileID = profile
        async let workspace = WorkspaceModel.load(from: locations.workspace(profile))
        async let preferences = PreferencesModel.load(from: locations.preferences(profile))
        async let promptHistory = PromptHistoryModel.load(from: locations.promptHistory(profile))
        async let reviews = PullRequestReviewsModel.load(from: locations.pullRequestReviews(profile))
        let (loadedWorkspace, loadedPreferences, loadedHistory) = await (workspace, preferences, promptHistory)
        pullRequestReviews = await reviews
        loadedWorkspace.update { $0.repair() }
        await SidebarProjectVisibility.migrate(loadedWorkspace, profile: profile)
        if loadedPreferences.document.startClean == true { loadedWorkspace.update { $0.startClean() } }
        showingHome = loadedPreferences.document.startOnHome == true && !loadedWorkspace.document.projects.isEmpty
        let tabs = Set(loadedWorkspace.document.projects.flatMap(\.panes).flatMap(\.tabs).map(\.id))
        if loadedHistory.document.histories.keys.contains(where: { !tabs.contains(TabID(rawValue: $0)) }) {
            loadedHistory.update { $0.prune(keeping: tabs) }
        }
        Self.removeOrphanScrollback(in: locations.scrollback(profile), keeping: tabs)
        Handoff.pruneOld(in: locations.handoffs(profile))
        let plugins = PluginHost(plugins: Self.builtinPlugins, dataRoot: locations.profileDirectory(profile),
                                 services: Self.pluginServices)
        TodosPlugin.onNewTodo = { [weak self] in
            guard let self else { return }
            self.showTodos()
            self.newTodoRequest += 1
        }
        GitControlPlugin.onOpen = { [weak self] in
            self?.openPluginSheet(GitControlPlugin.sheetID, project: nil)
        }
        await plugins.load()
        self.plugins = plugins
        let extensions = ExtensionManager(profileDirectory: locations.profileDirectory(profile))
        self.extensions = extensions
        plugins.events.attach(multiagent.bus)
        extensions.events.attach(multiagent.bus)
        Task { await extensions.start() }
        #if DEBUG
        if let seed = UserDefaults.standard.string(forKey: "AletheUITestSeed"), loadedWorkspace.document.projects.isEmpty {
            loadedWorkspace.update { TestSeeds.apply(seed, to: &$0) }
            loadedPreferences.update { TestSeeds.apply(seed, to: &$0) }
        }
        if let name = UserDefaults.standard.string(forKey: "AletheUITestPreview") {
            editorRequest = .previewLink(.file(locations.root.appending(path: name).path))
        }
        #endif
        terminals.hookEnvironment = self
        orchestrator.start(profileDirectory: locations.profileDirectory(profile), launchers: launchers,
                           overrides: { [weak self] in self?.preferences?.document.cliPaths ?? [:] },
                           isEnabled: { [weak self] in self?.features.isOn(.orchestrator) == true })
        OrchestratorWiring.start(environment: self)
        graphify.start(environment: self)
        playwright.start(profileDirectory: locations.browserSession(profile), wiring: terminals.mcp, environment: self)
        notifier.start(environment: self)
        await terminals.hooks.start(terminals: terminals)
        self.profiles = profiles
        self.workspace = loadedWorkspace
        if interfaceStyle == .web {
            for project in loadedWorkspace.document.projects where project.gsdWatcherEnabled == true {
                try? await multiagent.follow(projectID: project.id.rawValue, folder: URL(filePath: project.folder), by: .projectPreference)
            }
        }
        self.preferences = loadedPreferences
        await orchestrator.applySettings(loadedPreferences.document.orchestration ?? .init())
        await orchestrator.applyWorkerRules(interfaceStyle == .web ? loadedPreferences.document.workerRuleSets : [])
        aiMemory.start(environment: self)
        gsdSync.start(environment: self, profileDirectory: locations.profileDirectory(profile))
        mcp = makeMcpModel(profileDirectory: locations.profileDirectory(profile), preferences: loadedPreferences)
        followAppIcon()
        self.promptHistory = loadedHistory
        resources.start(environment: self)
        usage.start(environment: self)
        activity.start(environment: self, file: locations.activityStats(profile))
        dictation.start(environment: self)
        remoteControl.start(environment: self)
        discordPresence.start(environment: self)
        nowPlaying.start(environment: self)
        gistSync.start(environment: self)
        router9.start(environment: self)
        #if DEBUG
        if let seed = UserDefaults.standard.string(forKey: "AletheUITestSeed") { TestSeeds.apply(seed, to: self) }
        #endif
        let requested = pendingFolders
        pendingFolders = []
        requested.forEach(openFolder)
        if diagnostics.crashNotice != nil, editorRequest == nil, Self.showsCrashNotice { editorRequest = .crashNotice }
        greetLaunch()
        offerMcpIntro()
        #if DEBUG
        if ProcessInfo.processInfo.environment["ALETHE_SAMPLE_DATA"] == "1" { await loadSampleData() }
        #endif
        NotificationCenter.default.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                               object: NSWorkspace.shared, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemReducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }

    func openFolder(_ url: URL) {
        guard let workspace else {
            pendingFolders.append(url)
            return
        }
        let document = workspace.document
        let candidates = document.projects.map { (id: $0.id, folder: $0.folder) }
        let selected = document.workspace.selectedProjectID
        Task {
            let found: (folder: URL, project: ProjectID?)? = await Task.detached {
                guard let folder = CLILaunch.directory(for: url) else { return nil }
                return (folder, CLILaunch.match(folder: folder.path, in: candidates, preferred: selected))
            }.value
            guard let found else { return }
            if let project = found.project {
                self.workspace?.update { $0.open(project) }
                showingHome = false
            } else {
                editorRequest = .newProject(.ungrouped, folder: found.folder.path)
            }
            NSApp.activate()
        }
    }

    func openLaunchArguments() {
        guard let raw = CLILaunch.pathArgument(in: CommandLine.arguments) else { return }
        let cwd = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        let expanded = (raw as NSString).expandingTildeInPath
        openFolder(expanded.hasPrefix("/") ? URL(filePath: expanded) : cwd.appending(path: expanded))
    }

    func scrollbackFile(for tab: TabID) -> ScrollbackFile? {
        guard let locations, let profile = profileID else { return nil }
        return ScrollbackFile(url: locations.scrollback(profile).appending(path: "\(tab.rawValue).bin"))
    }

    private static func removeOrphanScrollback(in directory: URL, keeping tabs: Set<TabID>) {
        let names = Set(tabs.map { "\($0.rawValue).bin" })
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "bin" && !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    var runningTerminals: (agents: Int, shells: Int) {
        guard let document = workspace?.document else { return (0, 0) }
        var agents = 0, shells = 0
        for (tab, _) in terminals.running {
            if document.paneHolding(tab)?.pane.tabs.first(where: { $0.id == tab })?.agent == "shell" { shells += 1 } else { agents += 1 }
        }
        return (agents, shells)
    }

    func flush() async {
        await activity.finish()
        await remoteControl.stop()
        await router9.stop()
        await discordPresence.stop()
        await plugins?.shutdown()
        await extensions?.shutdown()
        terminals.terminateAll()
        await orchestrator.shutdown()
        terminals.hooks.stop()
        await playwright.stop()
        await multiagent.stop()
        await workspace?.flush()
        await preferences?.flush()
        await promptHistory?.flush()
        await pullRequestReviews?.flush()
        await profiles?.flush()
    }

    var todoStore: TodoStore? {
        guard plugins?.record(for: TodosPlugin.manifest.id)?.state == .active else { return nil }
        return TodosPlugin.activeStore
    }

    func showTodos() {
        rightSidebarTab = TodosPlugin.sidebarTabID
        rightSidebarVisible = true
    }

    private static let pluginServices = PluginServices(
        readFile: { url in
            try await Task.detached { try Data(contentsOf: url) }.value
        },
        writeFile: { data, url in
            try await Task.detached {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }.value
        }
    )

    static let builtinPlugins: [any AlethePlugin.Type] = [ThemePackPlugin.self, TodosPlugin.self, GitControlPlugin.self]

    func hasPluginCommand(_ id: String) -> Bool {
        plugins?.contributions.commands.contains { $0.id == id } == true
    }

    func performPluginCommand(_ id: String) {
        plugins?.contributions.commands.first { $0.id == id }?.perform()
    }

    func openPluginSheet(_ id: String, project: ProjectID?) {
        guard let sheet = plugins?.contributions.sheets.first(where: { $0.id == id }) else { return }
        editorRequest = .pluginSheet(viewID: sheet.viewID, project: project)
    }

    private func makeMcpModel(profileDirectory: URL, preferences: PreferencesModel) -> McpManagerModel {
        let model = McpManagerModel(
            store: McpStore(home: Self.mcpHome, writer: ConfigFileWriter(profileDirectory: profileDirectory)),
            registry: McpRegistry(profileDirectory: profileDirectory),
            healthAvailable: !Self.integrationsHomeOverridden,
            scope: preferences.document.mcpDefaultScope == McpScope.project.rawValue ? .project : .global
        )
        model.onScopeChange = { [weak preferences] scope in
            preferences?.update { $0.mcpDefaultScope = scope == .global ? nil : scope.rawValue }
        }
        return model
    }

    private func offerMcpIntro() {
        guard features.isOn(.mcp), preferences?.document.mcpOnboardingSeen != true, Self.showsMcpIntro,
              let store = mcp?.store else { return }
        if case .onboarding = editorRequest {
            preferences?.update { $0.mcpOnboardingSeen = true }
            return
        }
        Task {
            guard let snapshots = try? await store.scan(scope: .global, repository: nil) else { return }
            if snapshots.contains(where: { $0.sources.contains(where: \.exists) }) {
                if editorRequest == nil { editorRequest = .mcpIntro }
            } else {
                preferences?.update { $0.mcpOnboardingSeen = true }
            }
        }
    }

    private static var showsMcpIntro: Bool {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "AletheDataRoot") != nil {
            return UserDefaults.standard.bool(forKey: "AletheUITestMcpIntro")
        }
        #endif
        return true
    }

    private static var showsCrashNotice: Bool {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "AletheDataRoot") != nil {
            return UserDefaults.standard.bool(forKey: "AletheUITestCrashMarker")
        }
        #endif
        return true
    }

    private static func dataLocations() throws -> DataLocations {
        #if DEBUG
        if let root = UserDefaults.standard.string(forKey: "AletheDataRoot") {
            return DataLocations(root: URL(filePath: root, directoryHint: .isDirectory))
        }
        #endif
        return try DataLocations.application()
    }
}
