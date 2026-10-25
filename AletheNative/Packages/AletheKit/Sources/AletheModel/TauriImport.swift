import AletheFoundation
import Foundation

public enum TauriImport {
    public static let supportedVersions = 2...9

    public enum Failure: Error, Equatable, Sendable {
        case unreadable
        case unsupportedVersion(Int?)
    }

    public enum Skip: Hashable, Sendable {
        case projectWithoutFolder(project: String)
        case projectAlreadyAdded(project: String)
        case projectArchived(project: String)
        case paneKind(project: String, kind: String)
        case agent(project: String, agent: String)
    }

    public struct Report: Hashable, Sendable {
        public var groups = 0
        public var projects = 0
        public var panes = 0
        public var tabs = 0
        public var skipped: [Skip] = []
        public var preferences: Set<Preference> = []
        public var language: String?
        public var secrets: Set<KeychainItem> = []
        public var gistSync: GistSyncState?

        public init() {}

        public var isEmpty: Bool {
            groups == 0 && projects == 0 && preferences.isEmpty && language == nil && secrets.isEmpty && gistSync == nil
        }
    }

    public enum Preference: String, Hashable, Sendable, CaseIterable {
        case theme, interfaceSize, enabledAgents, alwaysUnrestricted, cliPaths, features, appIcon, toolbar, mcp
        case integrations
        case router9
        case remote
    }

    public struct Secrets: Sendable, CustomStringConvertible {
        public var values: [KeychainItem: Data] = [:]

        public init() {}

        public var description: String { "Secrets(\(values.keys.map(\.rawValue).sorted()))" }
    }

    public struct Companions: Sendable {
        public static let spotifyTokensFileName = "spotify_tokens.json"
        public static let githubSyncFileName = "github_sync.json"

        public var spotifyTokens: SpotifyTokens?
        public var githubToken: String?
        public var gistSync: GistSyncState?

        public init() {}

        public init(spotifyTokens: Data?, githubSync: Data?) {
            if let data = spotifyTokens, let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let access = raw["access_token"] as? String, let refresh = raw["refresh_token"] as? String,
               !access.isEmpty || !refresh.isEmpty {
                let expiry = (raw["expires_at"] as? Double) ?? 0
                self.spotifyTokens = SpotifyTokens(accessToken: access, refreshToken: refresh,
                                                   expiresAt: Date(timeIntervalSince1970: expiry))
            }
            if let data = githubSync, let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                githubToken = (raw["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                let login = (raw["login"] as? String)?.nilIfEmpty
                let gist = (raw["gist_id"] as? String)?.nilIfEmpty
                if login != nil || gist != nil { gistSync = GistSyncState(login: login, tauriGistID: gist) }
            }
        }

        public static func beside(_ projectsFile: URL) -> Companions {
            let folder = projectsFile.deletingLastPathComponent()
            return Companions(spotifyTokens: try? Data(contentsOf: folder.appending(path: spotifyTokensFileName)),
                              githubSync: try? Data(contentsOf: folder.appending(path: githubSyncFileName)))
        }
    }

    public struct Context: Sendable {
        public var agents: Set<String>
        public var themes: Set<String>
        public var includePreferences: Bool
        public var fileExists: @Sendable (String) -> Bool

        public init(agents: Set<String>, themes: Set<String>, includePreferences: Bool = true,
                    fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
            self.agents = agents
            self.themes = themes
            self.includePreferences = includePreferences
            self.fileExists = fileExists
        }
    }

    public struct File: @unchecked Sendable {
        public let version: Int
        let root: [String: Any]

        public init(data: Data) throws(Failure) {
            guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any] else {
                throw .unreadable
            }
            let version = root["version"] as? Int
            guard let version, TauriImport.supportedVersions.contains(version) else {
                throw .unsupportedVersion(version)
            }
            self.version = version
            self.root = root
        }

        var groups: [[String: Any]] { root["groups"] as? [[String: Any]] ?? [] }
        var projects: [[String: Any]] { root["projects"] as? [[String: Any]] ?? [] }
        var ungroupedOrder: [String] { root["ungroupedOrder"] as? [String] ?? [] }
        var preferences: [String: Any] { root["preferences"] as? [String: Any] ?? [:] }
        var cliPaths: [String: Any] { root["cliPaths"] as? [String: Any] ?? [:] }
    }

    @discardableResult
    public static func apply(_ file: File, companions: Companions = Companions(), to workspace: inout WorkspaceDocument,
                             preferences: inout PreferencesDocument, context: Context) -> Report {
        var report = Report()
        let groupIDs = importGroups(file, into: &workspace, report: &report)
        importProjects(file, into: &workspace, groupIDs: groupIDs, context: context, report: &report)
        importScopeGrids(file, into: &workspace, preferences: &preferences, groupIDs: groupIDs,
            includePreferences: context.includePreferences)
        if context.includePreferences {
            importPreferences(file, into: &preferences, context: context, report: &report)
            report.secrets = Set(secrets(in: file, companions: companions, context: context).values.keys)
            report.gistSync = companions.gistSync
        }
        return report
    }

    public static func secrets(in file: File, companions: Companions, context: Context) -> Secrets {
        var secrets = Secrets()
        guard context.includePreferences else { return secrets }
        let raw = file.preferences
        if let value = (raw["spotifyClientSecret"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            secrets.values[.spotifyClientSecret] = Data(value.utf8)
        }
        if let value = ((raw["router9"] as? [String: Any])?["apiKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            secrets.values[.router9APIKey] = Data(value.utf8)
        }
        if let tokens = companions.spotifyTokens, let data = try? JSONEncoder().encode(tokens) { secrets.values[.spotifyTokens] = data }
        if let token = companions.githubToken { secrets.values[.githubToken] = Data(token.utf8) }
        return secrets
    }

    static func orchestratorPane(from terminal: [String: Any]) -> Pane {
        let id = (terminal["id"] as? String).flatMap { $0.isEmpty ? nil : PaneID(rawValue: $0) } ?? .make()
        var pane = Pane(id: id, content: .orchestrator)
        pane.gridID = (terminal["gridId"] as? String).flatMap { $0.isEmpty || $0 == "default" ? nil : ProjectGridID(rawValue: $0) }
        return pane
    }

    public static let orchestratorJobsFileName = "orchestrator-jobs.json"

    @discardableResult
    public static func copyOrchestratorJobs(from projectsFile: URL, into profileDirectory: URL,
                                            fileManager: FileManager = .default) -> Bool {
        let source = projectsFile.deletingLastPathComponent().appending(path: orchestratorJobsFileName)
        let target = profileDirectory.appending(path: orchestratorJobsFileName)
        guard fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: target.path) else { return false }
        do {
            try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: target)
            return true
        } catch {
            return false
        }
    }

    static func pane(from terminal: [String: Any], folder: String, project: String, context: Context,
                             report: inout Report) -> Pane? {
        var tabs: [PaneTab] = []
        var activeTab: TabID?
        for tab in terminal["tabs"] as? [[String: Any]] ?? [] {
            let agent = tab["type"] as? String ?? "shell"
            guard context.agents.contains(agent) else {
                report.skipped.append(.agent(project: project, agent: agent))
                continue
            }
            let cwd = (tab["cwd"] as? String) ?? (terminal["cwd"] as? String)
            let own = cwd.flatMap { isAbsolute($0) && normalizedFolder($0) != normalizedFolder(folder) ? $0 : nil }
            var created = PaneTab(
                agent: agent,
                title: (tab["name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                workingDirectory: own,
                sessionID: (tab["sessionId"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                extraArguments: tab["extraArgs"] as? [String] ?? [],
                createdAt: (tab["lastUsedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            )
            if tab["useRouter9"] as? Bool == true { created.useRouter9 = true }
            if tab["id"] as? String == terminal["activeTabId"] as? String { activeTab = created.id }
            tabs.append(created)
        }
        guard !tabs.isEmpty else { return nil }
        let id = (terminal["id"] as? String).flatMap { $0.isEmpty ? nil : PaneID(rawValue: $0) } ?? .make()
        var pane = Pane(id: id, tabs: tabs, activeTabID: activeTab)
        pane.gridID = (terminal["gridId"] as? String).flatMap { $0.isEmpty || $0 == "default" ? nil : ProjectGridID(rawValue: $0) }
        if isRemoteShared(terminal) { pane.remoteShared = true }
        return pane
    }

    static func isRemoteShared(_ terminal: [String: Any]) -> Bool {
        (terminal["remoteShared"] as? Bool) ?? (terminal["remoteExcluded"] as? Bool != true)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
