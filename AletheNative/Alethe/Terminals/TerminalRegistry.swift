import AletheAgents
import AletheDesign
import AletheFoundation
import AletheIntegrations
import AletheModel
import AletheTerminal
import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class TerminalRegistry {
    enum State: Equatable {
        case running
        case exited(code: Int32)
        case forceKilled
        case notFound(command: String)
        case failed(message: String)
    }

    private(set) var states: [TabID: State] = [:]
    private(set) var pageOffers: [TabID: URL] = [:]
    private(set) var generations: [TabID: Int] = [:]
    private(set) var hibernated: Set<TabID> = []
    private(set) var activity: [TabID: AgentActivity] = [:]
    @ObservationIgnored var onActivityChange: ((TabID, AgentActivity, AgentHookEvent?) -> Void)?
    @ObservationIgnored let hooks = AgentHookHub()
    @ObservationIgnored let mcp = McpLaunchWiring()
    private(set) var titles: [TabID: String] = [:]
    private(set) var unread: Set<TabID> = []
    @ObservationIgnored private var watches: [TabID: ActivityWatch] = [:]
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var views: [TabID: TerminalPaneView] = [:]
    @ObservationIgnored private var claims = SessionClaims()
    @ObservationIgnored private var launches: [TabID: (startedAt: ContinuousClock.Instant, resumed: Bool)] = [:]
    @ObservationIgnored private var retriedFresh: Set<TabID> = []
    @ObservationIgnored private var scrollbacks: [TabID: ScrollbackFile] = [:]
    @ObservationIgnored private var discoveries: [TabID: Task<Void, Never>] = [:]
    @ObservationIgnored private var preparing: Set<TabID> = []
    @ObservationIgnored let output = TerminalOutputRelay()

    func view(for tab: TabID) -> TerminalPaneView? { views[tab] }

    func ensureStarted(_ tab: PaneTab, in project: Project, environment: AppEnvironment) {
        guard states[tab.id] == nil, !preparing.contains(tab.id) else { return }
        start(tab, in: project, environment: environment)
    }

    func restart(_ tab: PaneTab, in project: Project, environment: AppEnvironment) {
        restart(tab, in: project, environment: environment, fresh: false)
    }

    private func restart(_ tab: PaneTab, in project: Project, environment: AppEnvironment, fresh: Bool) {
        if let view = views.removeValue(forKey: tab.id) {
            view.terminate()
            output.exit(tab.id, reason: "restarted")
        }
        scrollback(for: tab.id, environment: environment)?.clear()
        environment.launchers.invalidate()
        start(tab, in: project, environment: environment, fresh: fresh)
    }

    func close(_ tab: TabID, keepScrollback: Bool = false, exitReason: String = "killed") {
        let view = views.removeValue(forKey: tab)
        if view != nil, states[tab] == .running { output.exit(tab, reason: exitReason) }
        pageOffers.removeValue(forKey: tab)
        if let file = scrollbacks.removeValue(forKey: tab) {
            if keepScrollback { file.flush() } else { file.delete() }
        }
        view?.terminate()
        states.removeValue(forKey: tab)
        generations.removeValue(forKey: tab)
        discoveries.removeValue(forKey: tab)?.cancel()
        preparing.remove(tab)
        watches.removeValue(forKey: tab)?.stop()
        if watches.isEmpty {
            ticker?.invalidate()
            ticker = nil
        }
        activity.removeValue(forKey: tab)
        unread.remove(tab)
        launches.removeValue(forKey: tab)
        retriedFresh.remove(tab)
        claims.release(owner: tab.rawValue)
    }

    func apply(_ event: AgentHookEvent, to tab: TabID) {
        guard states[tab] == .running else { return }
        if let session = event.sessionID, let environment = hookEnvironment,
           let (project, pane) = environment.workspace?.document.paneHolding(tab),
           let item = pane.tabs.first(where: { $0.id == tab }), item.sessionID != session {
            let cwd = item.workingDirectory ?? project.folder
            claims.release(owner: tab.rawValue)
            claims.register(AgentKind(rawValue: item.agent), cwd: cwd, sessionID: session, owner: tab.rawValue)
            environment.workspace?.update { $0.updateTab(tab) { $0.sessionID = session } }
        }
        if let next = event.activity { setActivity(next, for: tab, event: event) }
    }

    @ObservationIgnored weak var hookEnvironment: AppEnvironment?

    private func setActivity(_ next: AgentActivity, for tab: TabID, event: AgentHookEvent? = nil) {
        guard activity[tab] != next else { return }
        activity[tab] = next
        if next == .done || next == .needsInput {
            if !isInFront(tab) { unread.insert(tab) }
            refreshTitle(tab)
        }
        onActivityChange?(tab, next, event)
    }

    func isInFront(_ tab: TabID) -> Bool {
        guard NSApp.isActive, let document = hookEnvironment?.workspace?.document,
              let pane = document.workspace.focusedPaneID else { return false }
        return document.pane(pane)?.pane.activeTab?.id == tab
    }

    func markRead(_ tab: TabID) {
        unread.remove(tab)
    }

    func refreshTitle(_ tab: TabID) {
        guard let document = hookEnvironment?.workspace?.document, let (project, pane) = document.paneHolding(tab),
              let item = pane.tabs.first(where: { $0.id == tab }), let session = item.sessionID else { return }
        let kind = AgentKind(rawValue: item.agent), cwd = item.workingDirectory ?? project.folder
        Task { [weak self] in
            let title = await Task.detached { ConversationHistory.title(kind, sessionID: session, cwd: cwd) }.value
            guard let self, let title, self.titles[tab] != title else { return }
            self.titles[tab] = title
        }
    }

    func displayName(of tab: PaneTab) -> String {
        tab.title ?? titles[tab.id] ?? AgentLabels.name(for: tab.agent)
    }

    private func watch(_ tab: TabID, view: TerminalPaneView, heuristicTurns: Bool) {
        watches.removeValue(forKey: tab)?.stop()
        let watch = ActivityWatch(tap: view.tap, endsTurns: heuristicTurns) { [weak self] next in
            Task { @MainActor in self?.setActivity(next, for: tab) }
        }
        watches[tab] = watch
        setActivity(.idle, for: tab)
        if ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.watches.values.forEach { $0.tick() } }
            }
        }
    }

    var running: [(tab: TabID, view: TerminalPaneView)] {
        states.compactMap { tab, state in state == .running ? views[tab].map { (tab, $0) } : nil }
    }

    func hibernate(_ tab: TabID) {
        guard states[tab] == .running else { return }
        close(tab, keepScrollback: true, exitReason: "suspended")
        hibernated.insert(tab)
    }

    func resumePreviousConversations(environment: AppEnvironment) -> (resumed: Int, total: Int) {
        guard let document = environment.workspace?.document else { return (0, 0) }
        var resumed = 0, total = 0
        for (tab, view) in running {
            guard let (project, pane) = document.paneHolding(tab), let item = pane.tabs.first(where: { $0.id == tab }) else { continue }
            let kind = AgentKind(rawValue: item.agent)
            guard kind != .shell else { continue }
            total += 1
            let sessions = SessionResume.sessions(kind, cwd: item.workingDirectory ?? project.folder)
            guard let previous = SessionResume.previous(in: sessions, excluding: item.sessionID, before: view.startedAt)
            else { continue }
            environment.workspace?.update { $0.updateTab(tab) { $0.sessionID = previous } }
            var next = item
            next.sessionID = previous
            restart(next, in: project, environment: environment)
            resumed += 1
        }
        return (resumed, total)
    }

    func suspend(_ tab: TabID) {
        guard states[tab] != nil else { return }
        close(tab, keepScrollback: true, exitReason: "suspended")
    }

    func dismissPageOffer(for tab: TabID) {
        pageOffers.removeValue(forKey: tab)
    }

    func prune(keeping tabs: Set<TabID>) {
        for tab in Set(states.keys).subtracting(tabs) { close(tab) }
        hibernated.formIntersection(tabs)
    }

    func terminateAll() {
        for tab in Array(states.keys) { close(tab, keepScrollback: true) }
    }

    func applyAppearance(theme: Theme, fontSize: Float) {
        for view in views.values { view.applyTheme(theme, fontSize: fontSize) }
    }

    private func scrollback(for tab: TabID, environment: AppEnvironment) -> ScrollbackFile? {
        if let file = scrollbacks[tab] { return file }
        let file = environment.scrollbackFile(for: tab)
        scrollbacks[tab] = file
        return file
    }

    private func deliver(_ prompt: String, to view: TerminalPaneView, tab: TabID,
                         style: PromptDelivery.Style, environment: AppEnvironment) {
        Task { [weak environment] in
            guard await view.deliverPrompt(prompt, style: style) else { return }
            environment?.workspace?.update { $0.updateTab(tab) { $0.initialPrompt = nil } }
        }
    }

    private func resumableSession(of tab: PaneTab, kind: AgentKind, cwd: String, fresh: Bool) -> String? {
        guard !fresh, let id = tab.sessionID else { return nil }
        if claims.isClaimed(kind, cwd: cwd, sessionID: id, excluding: tab.id.rawValue) { return nil }
        return SessionResume.isResumable(kind, sessionID: id, cwd: cwd) ? id : nil
    }

    private func discoverSession(for tab: TabID, kind: AgentKind, cwd: String, before beforeTask: Task<Set<String>, Never>,
                                 executable: String?, environment: AppEnvironment) {
        discoveries[tab] = Task { [weak self, weak environment] in
            let before = await beforeTask.value
            let found = await SessionResume.discover(sleep: { try? await Task.sleep(for: $0) }) {
                let sessions = await Task.detached { await SessionResume.snapshot(kind, cwd: cwd, executable: executable) }.value
                return self?.claims.claimDiscovered(kind, cwd: cwd, before: before, sessions: sessions,
                                                    owner: tab.rawValue)?.id
            }
            guard let found, let self, !Task.isCancelled else { return }
            self.discoveries.removeValue(forKey: tab)
            environment?.workspace?.update { $0.updateTab(tab) { $0.sessionID = found } }
        }
    }

    private func start(_ tab: PaneTab, in project: Project, environment: AppEnvironment, fresh: Bool = false) {
        hibernated.remove(tab.id)
        let kind = AgentKind(rawValue: tab.agent)
        let cwd = tab.workingDirectory ?? project.folder
        if kind == .cursor, tab.sessionID == nil, !preparing.contains(tab.id),
           let executable = environment.launchers.resolve("cursor-agent", override: environment.preferences?.document.cliPaths?["cursor"]) {
            preparing.insert(tab.id)
            Task { [weak self, weak environment] in
                let chat = await CursorChats.create(executable: executable, cwd: cwd)
                guard let self, let environment else { return }
                var prepared = tab
                if let chat {
                    prepared.sessionID = chat
                    environment.workspace?.update { $0.updateTab(tab.id) { $0.sessionID = chat } }
                }
                guard self.preparing.remove(tab.id) != nil, environment.workspace?.document.paneHolding(tab.id) != nil else { return }
                self.startPrepared(prepared, in: project, environment: environment, fresh: fresh)
            }
            return
        }
        let syncsGSD = kind == .opencode && environment.features.isOn(.gsdSync)
        let routes = Router9.wantsRouting(tab)
        if syncsGSD || routes, !preparing.contains(tab.id) {
            preparing.insert(tab.id)
            Task { [weak self, weak environment] in
                if syncsGSD { await environment?.gsdSync.prepareLaunch(in: cwd) }
                let config = routes ? await environment?.router9.routingConfig() : nil
                guard let self, let environment, self.preparing.remove(tab.id) != nil,
                      environment.workspace?.document.paneHolding(tab.id) != nil else { return }
                self.startPrepared(tab, in: project, environment: environment, fresh: fresh,
                                   routing: Router9.launchEnvironment(for: tab, config: config))
            }
            return
        }
        startPrepared(tab, in: project, environment: environment, fresh: fresh)
    }

    private func startPrepared(_ tab: PaneTab, in project: Project, environment: AppEnvironment, fresh: Bool,
                               routing: [String: String] = [:]) {
        let kind = AgentKind(rawValue: tab.agent)
        let cwd = tab.workingDirectory ?? project.folder
        discoveries.removeValue(forKey: tab.id)?.cancel()
        claims.release(owner: tab.id.rawValue)
        let sessionID = resumableSession(of: tab, kind: kind, cwd: cwd, fresh: fresh)
        let servers = mcp.launch(for: McpLaunchContext(tab: tab.id, kind: kind, project: project, workingDirectory: cwd))
        let request = AgentLaunchRequest(
            kind: kind,
            workingDirectory: cwd,
            extraArguments: tab.extraArguments,
            sessionID: sessionID,
            unrestricted: tab.unrestricted,
            hooks: hooks.launch(for: tab.id, kind: kind, orchestrator: environment.features.isOn(.orchestrator)),
            mcpServers: servers.servers,
            mcpConfigPath: servers.configPath,
            environment: routing
        )
        do {
            let command = try environment.agentLauncher.command(for: request)
            let before = sessionSnapshot(kind: kind, command: command, cwd: cwd)
            let view = try makeTerminal(command: command, tab: tab, kind: kind, environment: environment)
            wire(view, tab: tab, project: project, environment: environment)
            let relay = output, tabID = tab.id
            view.tap.observeOutput { data in relay.output(tabID, data) }
            views[tab.id] = view
            states[tab.id] = .running
            let variables = command.environment.keys.sorted().joined(separator: ",")
            Diagnostics.shared.recordSpawn("started agent=\(kind.rawValue) pid=\(view.processID) cwd=\(cwd) "
                + "executable=\(command.executable ?? "-") resumed=\(sessionID != nil) env=[\(variables)] "
                + "command=\(command.shellCommand ?? "login shell")")
            if kind != .shell {
                watch(tab.id, view: view, heuristicTurns: !hooks.reportsTurns(kind))
                if tab.sessionID != nil { refreshTitle(tab.id) }
            }
            launches[tab.id] = (.now, sessionID != nil)
            if let prompt = tab.initialPrompt, kind != .shell {
                deliver(prompt, to: view, tab: tab.id, style: kind == .opencode ? .typeAndConfirm : .paste,
                        environment: environment)
            }
            if let session = command.sessionID {
                claims.register(kind, cwd: cwd, sessionID: session, owner: tab.id.rawValue)
            }
            if command.sessionID != tab.sessionID, kind != .shell {
                environment.workspace?.update { $0.updateTab(tab.id) { $0.sessionID = command.sessionID } }
            }
            if let before {
                discoverSession(for: tab.id, kind: kind, cwd: cwd, before: before, executable: command.executable,
                                environment: environment)
            }
        } catch AgentLaunchError.launcherNotFound(let command) {
            states[tab.id] = .notFound(command: command)
            Diagnostics.shared.recordSpawn("not found agent=\(kind.rawValue) command=\(command) cwd=\(cwd)")
            AppLog.record(.warning, .agents, "\(kind.rawValue): \(command) not found")
        } catch {
            states[tab.id] = .failed(message: String(describing: error))
            Diagnostics.shared.recordSpawn("failed agent=\(kind.rawValue) cwd=\(cwd) error=\(error)")
            AppLog.record(.error, .terminal, "\(kind.rawValue) did not start: \(error)")
        }
        generations[tab.id, default: 0] += 1
    }
    private func wire(_ view: TerminalPaneView, tab: PaneTab, project: Project, environment: AppEnvironment) {
        view.onOpenLink = { [weak environment, weak view] link in
            guard let environment, let view else { return }
            environment.openTerminalLink(link, from: view, tab: tab, project: project)
        }
        view.onLocalServer = { [weak self] url in self?.pageOffers[tab.id] = url }
        view.onPromptHistoryChange = { [weak environment] entries in
            environment?.promptHistory?.update { $0.histories[tab.id.rawValue] = entries }
        }
        view.onExit = { [weak self, weak view, weak environment] code in
            guard let self, let view, self.views[tab.id] === view else { return }
            if !view.wasForceKilled, let launch = self.launches[tab.id], let environment,
               SessionResume.shouldRetryFresh(resumed: launch.resumed, elapsed: .now - launch.startedAt,
                                              alreadyRetried: self.retriedFresh.contains(tab.id)) {
                self.retriedFresh.insert(tab.id)
                self.restart(tab, in: project, environment: environment, fresh: true)
                return
            }
            self.states[tab.id] = view.wasForceKilled ? .forceKilled : .exited(code: code)
            self.output.exit(tab.id, reason: view.wasForceKilled ? "killed" : "exited")
        }
    }

    private func sessionSnapshot(kind: AgentKind, command: AgentCommand, cwd: String) -> Task<Set<String>, Never>? {
        var before: Task<Set<String>, Never>?
        if SessionResume.discoversNewSessions(kind) && command.sessionID == nil {
            if kind == .opencode {
                let executable = command.executable
                before = Task.detached { Set(await SessionResume.snapshot(kind, cwd: cwd, executable: executable).map(\.id)) }
            } else {
                let ids = Set(SessionResume.sessions(kind, cwd: cwd).map(\.id))
                before = Task { ids }
            }
        }
        return before
    }

    private func makeTerminal(command: AgentCommand, tab: PaneTab, kind: AgentKind,
                              environment: AppEnvironment) throws -> TerminalPaneView {
        let scrollbackFile = scrollback(for: tab.id, environment: environment)
        if kind != .shell { scrollbackFile?.clear() }
        return try TerminalPaneView(launch: command.ptyLaunch(size: PTYSize(columns: 80, rows: 24)),
                                        theme: environment.theme, fontSize: environment.terminalFontSize,
                                        forceKillNotice: String(localized: "terminal.forceKilled"),
                                        promptHistory: environment.promptHistory?.document.histories[tab.id.rawValue] ?? [],
                                        scrollback: scrollbackFile)
    }
}

extension TerminalRegistry {
    func typeInput(_ text: String, into tab: TabID) -> Bool {
        guard states[tab] == .running, let view = views[tab] else { return false }
        view.type(text)
        return true
    }

    func gridSize(of tab: TabID) -> PTYSize? {
        guard states[tab] == .running else { return nil }
        return views[tab]?.gridSize
    }

    func scrollbackFile(of tab: TabID) -> ScrollbackFile? {
        scrollbacks[tab] ?? views[tab]?.scrollback
    }

    nonisolated static func scrollbackTail(_ file: ScrollbackFile, maxBytes: Int) async -> Data {
        await Task.detached(priority: .utility) {
            file.flush()
            guard let handle = try? FileHandle(forReadingFrom: file.url) else { return Data() }
            defer { try? handle.close() }
            guard let end = try? handle.seekToEnd() else { return Data() }
            try? handle.seek(toOffset: end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0)
            return (try? handle.readToEnd()) ?? Data()
        }.value
    }
}

final class TerminalOutputRelay: @unchecked Sendable {
    enum Event: Sendable {
        case data(TabID, Data)
        case exit(TabID, reason: String)
    }

    private let lock = NSLock()
    private var observers: [UUID: @Sendable (Event) -> Void] = [:]

    func observe(_ observer: @escaping @Sendable (Event) -> Void) -> UUID {
        let id = UUID()
        lock.withLock { observers[id] = observer }
        return id
    }

    func remove(_ id: UUID) {
        lock.withLock { _ = observers.removeValue(forKey: id) }
    }

    func output(_ tab: TabID, _ data: Data) {
        send(.data(tab, data))
    }

    func exit(_ tab: TabID, reason: String) {
        send(.exit(tab, reason: reason))
    }

    private func send(_ event: Event) {
        let current = lock.withLock { Array(observers.values) }
        for observer in current { observer(event) }
    }
}

final class ActivityWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var monitor = ActivityMonitor()
    private let tap: TerminalIOTap
    private var observers: [UUID] = []
    private let endsTurns: Bool
    private let report: @Sendable (AgentActivity) -> Void

    init(tap: TerminalIOTap, endsTurns: Bool, report: @escaping @Sendable (AgentActivity) -> Void) {
        self.tap = tap
        self.endsTurns = endsTurns
        self.report = report
        observers.append(tap.observeInput { [weak self] data in
            guard let self else { return }
            let now = Date().timeIntervalSinceReferenceDate
            if let next = self.lock.withLock({ self.monitor.input(String(decoding: data, as: UTF8.self), at: now) }) {
                self.report(next)
            }
        })
        observers.append(tap.observeOutput { [weak self] data in
            guard let self else { return }
            let now = Date().timeIntervalSinceReferenceDate
            self.lock.withLock { self.monitor.output(String(decoding: data, as: UTF8.self), at: now) }
        })
    }

    func tick() {
        guard endsTurns else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if let next = lock.withLock({ monitor.tick(at: now) }) { report(next) }
    }

    func stop() {
        for id in observers { tap.remove(id) }
    }
}
