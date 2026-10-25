import AletheDesign
import AletheFoundation
import AletheIntegrations
import Foundation
import Observation

@MainActor @Observable
final class McpManagerModel {
    struct RevealKey: Hashable {
        let agent: McpAgent
        let source: URL
        let server: String
        let key: String
        let header: Bool
    }

    let store: McpStore
    let registry: McpRegistry
    private let health: McpHealthChecker
    let healthAvailable: Bool

    private(set) var scope: McpScope
    private(set) var repository: URL?
    private(set) var snapshots: [McpAgentSnapshot]?
    private(set) var groups: [McpServerGroup] = []
    private(set) var loading = false
    private(set) var busy = false
    private(set) var error: String? { didSet { if error != oldValue { AppLog.shown(error, .integrations) } } }
    private(set) var note: String?
    private(set) var undoLabel: String?
    private(set) var healthByAgent: [McpAgent: [McpHealth]] = [:]
    private(set) var healthErrors: [McpAgent: McpHealthError] = [:]
    private(set) var checking: Set<McpAgent> = []
    private(set) var revealed: [RevealKey: String] = [:]
    @ObservationIgnored var onScopeChange: ((McpScope) -> Void)?

    @ObservationIgnored private var undoAction: (() async throws -> Void)?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var healthTasks: [McpAgent: Task<Void, Never>] = [:]
    @ObservationIgnored private var checkedOnce = false

    init(store: McpStore, registry: McpRegistry, health: McpHealthChecker = McpHealthChecker(),
         healthAvailable: Bool, scope: McpScope) {
        self.store = store
        self.registry = registry
        self.health = health
        self.healthAvailable = healthAvailable
        self.scope = scope
    }

    var effectiveScope: McpScope { repository == nil ? .global : scope }

    var writableAgents: [McpAgent] { (snapshots ?? []).filter(\.isWritable).map(\.agent) }

    var issues: [(agent: McpAgent, issue: McpSnapshotIssue)] {
        (snapshots ?? []).compactMap { snapshot in snapshot.issue.map { (snapshot.agent, $0) } }
    }

    func group(named name: String) -> McpServerGroup? { groups.first { $0.name == name } }

    func snapshot(_ agent: McpAgent) -> McpAgentSnapshot? { snapshots?.first { $0.agent == agent } }

    func setRepository(_ folder: String?) {
        let url = folder.flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
        guard url != repository || snapshots == nil else { return }
        if url != repository { revealed = [:] }
        repository = url
        Task { await refresh() }
    }

    func setScope(_ next: McpScope) {
        guard next != scope else { return }
        scope = next
        revealed = [:]
        onScopeChange?(next)
        Task { await refresh() }
    }

    func refresh() async {
        loadTask?.cancel()
        let store = store, scope = effectiveScope, repository = repository
        loading = true
        let task = Task {
            do {
                let snapshots = try await store.scan(scope: scope, repository: repository)
                try Task.checkCancellation()
                self.snapshots = snapshots
                groups = McpStore.groups(snapshots)
                error = nil
            } catch is CancellationError {
                return
            } catch {
                snapshots = snapshots ?? []
                self.error = Self.describe(error)
            }
            loading = false
        }
        loadTask = task
        await task.value
    }

    func close() {
        revealed = [:]
    }

    func cancel() {
        loadTask?.cancel()
        healthTasks.values.forEach { $0.cancel() }
        healthTasks = [:]
        checking = []
        loading = false
    }

    var healthAgents: [McpAgent] { McpAgent.allCases.filter { McpHealthParser.cli(for: $0) != nil } }

    func status(of name: String, on agent: McpAgent) -> McpHealthStatus? {
        guard let reported = healthByAgent[agent] else { return nil }
        return reported.first { $0.name == name }?.status ?? .unknown
    }

    func status(of group: McpServerGroup) -> McpHealthStatus? {
        let statuses = group.agents.compactMap { agent in healthByAgent[agent]?.first { $0.name == group.name }?.status }
        guard !statuses.isEmpty else { return nil }
        for status in [McpHealthStatus.failed, .needsAuth, .disabled, .unknown] where statuses.contains(status) {
            return status
        }
        return .connected
    }

    func checkHealthOnce() {
        guard healthAvailable, !checkedOnce else { return }
        checkedOnce = true
        checkAllHealth()
    }

    func checkAllHealth() {
        let present = Set(groups.flatMap(\.agents))
        healthAgents.filter(present.contains).forEach(checkHealth)
    }

    func checkHealth(_ agent: McpAgent) {
        guard healthAvailable, !checking.contains(agent) else { return }
        checking.insert(agent)
        let health = health
        healthTasks[agent] = Task {
            do {
                healthByAgent[agent] = try await health.check(agent)
                healthErrors[agent] = nil
            } catch {
                if let failure = error as? McpHealthError, failure != .cancelled { healthErrors[agent] = failure }
            }
            checking.remove(agent)
            healthTasks[agent] = nil
        }
    }

    func toggle(_ record: McpServerRecord) async {
        let enabled = !record.server.enabled
        let name = record.server.name
        let label = format(enabled ? "mcp.note.enabled" : "mcp.note.disabled", name, record.agent.label)
        await change(label: label) { store, repository in
            _ = try await store.mutate(.setEnabled(name: name, enabled: enabled), agent: record.agent, scope: record.scope,
                                       repository: repository, sourceKind: record.sourceKind)
            return { [store] in
                _ = try await store.mutate(.setEnabled(name: name, enabled: !enabled), agent: record.agent,
                                           scope: record.scope, repository: repository, sourceKind: record.sourceKind)
            }
        }
    }

    func remove(_ records: [McpServerRecord]) async {
        guard let name = records.first?.server.name else { return }
        let label = format("mcp.note.removed", name, Self.labels(records.map(\.agent)))
        await change(label: label, undoable: false) { store, repository in
            for record in records {
                _ = try await store.mutate(.remove(name: record.server.name), agent: record.agent, scope: record.scope,
                                           repository: repository, sourceKind: record.sourceKind)
            }
            return nil
        }
    }

    func save(_ draft: McpServerDraft, over record: McpServerRecord) async throws(McpStoreError) {
        let server = try draft.server()
        let previous = record.server
        await change(label: format("mcp.note.saved", server.name, record.agent.label)) { store, repository in
            _ = try await store.mutate(.upsert(server), agent: record.agent, scope: record.scope, repository: repository,
                                       sourceKind: record.sourceKind)
            return { [store] in
                _ = try await store.mutate(.upsert(previous), agent: record.agent, scope: record.scope,
                                           repository: repository, sourceKind: record.sourceKind)
            }
        }
    }

    func add(_ draft: McpServerDraft, to targets: [McpAgent]) async throws(McpStoreError) {
        let server = try draft.server()
        let existing = Set(group(named: server.name)?.agents ?? [])
        let scope = effectiveScope
        busy = true
        error = nil
        note = nil
        var written: [McpAgent] = []
        var failures: [String] = []
        for agent in targets where !existing.contains(agent) {
            do {
                _ = try await store.mutate(.upsert(server), agent: agent, scope: scope, repository: repository)
                written.append(agent)
            } catch {
                failures.append("\(agent.label): \(Self.describe(error))")
            }
        }
        let skipped = targets.filter(existing.contains)
        var parts: [String] = []
        if !written.isEmpty { parts.append(format("mcp.note.added", server.name, Self.labels(written))) }
        if !skipped.isEmpty { parts.append(format("mcp.note.skipped", Self.labels(skipped))) }
        note = parts.isEmpty ? nil : parts.joined(separator: " ")
        if !failures.isEmpty { error = format("mcp.error.writeFailed", failures.joined(separator: " · ")) }
        if written.isEmpty {
            clearUndo()
        } else {
            let store = store, repository = repository, name = server.name
            setUndo(format("mcp.undo.add", server.name)) {
                for agent in written {
                    _ = try await store.mutate(.remove(name: name), agent: agent, scope: scope, repository: repository)
                }
            }
        }
        await refresh()
        busy = false
    }

    func sync(_ group: McpServerGroup, to targets: [McpAgent]) async {
        guard let from = group.records.first?.agent, !targets.isEmpty else { return }
        busy = true
        error = nil
        note = nil
        do {
            let outcomes = try await store.sync(name: group.name, from: from, to: targets, scope: effectiveScope,
                                                repository: repository)
            let written = outcomes.filter { if case .written = $0.status { true } else { false } }.map(\.agent)
            let skipped = outcomes.filter { $0.status == .skipped }.map(\.agent)
            var parts: [String] = []
            if !written.isEmpty { parts.append(format("mcp.note.synced", group.name, Self.labels(written))) }
            if !skipped.isEmpty { parts.append(format("mcp.note.skipped", Self.labels(skipped))) }
            var problems: [String] = []
            for outcome in outcomes {
                if case .blocked(let fields) = outcome.status {
                    problems.append(format("mcp.sync.blocked", outcome.agent.label, fields.map(\.field).joined(separator: ", ")))
                } else if case .failed(let failure) = outcome.status {
                    problems.append("\(outcome.agent.label): \(Self.describe(failure))")
                } else if case .written = outcome.status {
                } else if case .skipped = outcome.status {
                }
            }
            note = parts.isEmpty ? nil : parts.joined(separator: " ")
            error = problems.isEmpty ? nil : problems.joined(separator: " · ")
            if written.isEmpty {
                clearUndo()
            } else {
                let store = store, repository = repository, scope = effectiveScope, name = group.name
                setUndo(format("mcp.undo.sync", group.name)) {
                    for agent in written {
                        _ = try await store.mutate(.remove(name: name), agent: agent, scope: scope, repository: repository)
                    }
                }
            }
        } catch {
            self.error = Self.describe(error)
        }
        await refresh()
        busy = false
    }

    func performUndo() async {
        guard let action = undoAction else { return }
        let label = undoLabel
        clearUndo()
        busy = true
        do {
            try await action()
            note = label.map { format("mcp.note.undone", $0) }
            error = nil
        } catch {
            self.error = Self.describe(error)
        }
        await refresh()
        busy = false
    }

    private func change(label: String, undoable: Bool = true,
                        _ body: (McpStore, URL?) async throws -> (() async throws -> Void)?) async {
        busy = true
        error = nil
        note = nil
        do {
            let undo = try await body(store, repository)
            note = label
            if undoable, let undo { setUndo(label, undo) } else { clearUndo() }
        } catch {
            self.error = Self.describe(error)
        }
        await refresh()
        busy = false
    }

    private func setUndo(_ label: String, _ action: @escaping () async throws -> Void) {
        undoLabel = label
        undoAction = action
    }

    private func clearUndo() {
        undoLabel = nil
        undoAction = nil
    }

    func key(_ record: McpServerRecord, _ key: String, header: Bool) -> RevealKey {
        RevealKey(agent: record.agent, source: record.sourceURL, server: record.server.name, key: key, header: header)
    }

    func reveal(_ record: McpServerRecord, key: String, header: Bool) async {
        do {
            let value = try await store.reveal(agent: record.agent, scope: record.scope, repository: repository,
                                               name: record.server.name, key: key, header: header)
            revealed[self.key(record, key, header: header)] = value
        } catch {
            self.error = Self.describe(error)
        }
    }

    func hide(_ key: RevealKey) {
        revealed[key] = nil
    }

    func backups(for record: McpServerRecord) async -> [ConfigBackup] {
        guard let source = store.source(of: record, repository: repository) else { return [] }
        let store = store
        return await Task.detached { store.backups(agent: record.agent, source: source) }.value
    }

    func restore(_ backup: ConfigBackup, for record: McpServerRecord) async {
        guard let source = store.source(of: record, repository: repository) else { return }
        let label = format("mcp.note.restored", record.sourceURL.lastPathComponent,
                           backup.createdAt.formatted(date: .abbreviated, time: .standard))
        await change(label: label, undoable: false) { store, _ in
            _ = try await store.restore(backup, agent: record.agent, source: source)
            return nil
        }
    }

    static func labels(_ agents: [McpAgent]) -> String {
        agents.map(\.label).joined(separator: ", ")
    }

    static func describe(_ error: any Error) -> String {
        guard let error = error as? McpStoreError else {
            return error is CancellationError ? String(localized: "mcp.error.cancelled") : error.localizedDescription
        }
        if case .unsupportedScope = error {
            return String(localized: "mcp.error.unsupportedScope")
        } else if case .notFound = error {
            return String(localized: "mcp.error.notFound")
        } else if case .invalidName = error {
            return String(localized: "mcp.error.invalidName")
        } else if case .invalidCommand = error {
            return String(localized: "mcp.error.invalidCommand")
        } else if case .invalidURL = error {
            return String(localized: "mcp.error.invalidURL")
        } else if case .unsupportedFields(let fields) = error {
            return format("mcp.error.unsupportedFields", fields.map(\.field).joined(separator: ", "))
        } else if case .selfCheckFailed = error {
            return String(localized: "mcp.error.selfCheck")
        } else if case .backupMismatch = error {
            return String(localized: "mcp.error.backupMismatch")
        } else if case .cancelled = error {
            return String(localized: "mcp.error.cancelled")
        } else if case .config(.jsoncUnsupported) = error {
            return String(localized: "mcp.error.jsonc")
        } else if case .config(.unsupportedDisable) = error {
            return String(localized: "mcp.error.unsupportedDisable")
        } else if case .config(let config) = error {
            return format("mcp.error.config", config.description)
        } else if case .file(.changedSinceRead) = error {
            return String(localized: "mcp.error.changed")
        } else {
            return format("mcp.error.file", error.description)
        }
    }
}

extension McpAgent {
    private static let labelValues: [McpAgent: String] = [
        .claude: "Claude Code",
        .codex: "Codex",
        .cursor: "Cursor",
        .opencode: "OpenCode",
    ]

    var label: String {
        Self.labelValues[self] ?? "Antigravity"
    }

    private static let colorTokenValues: [McpAgent: ThemeToken] = [
        .claude: .agentClaude,
        .codex: .agentCodex,
        .cursor: .agentCursor,
        .opencode: .agentOpencode,
    ]

    var colorToken: ThemeToken {
        Self.colorTokenValues[self] ?? .agentAntigravity
    }
}
