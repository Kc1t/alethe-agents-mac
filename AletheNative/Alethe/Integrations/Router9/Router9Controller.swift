import AletheFoundation
import AletheIntegrations
import AletheModel
import Foundation
import Observation

@Observable
@MainActor
final class Router9Controller {
    enum Failure: Equatable {
        case service(Router9Error)
        case keychain
    }

    private(set) var status: Router9Status?
    private(set) var hasNPM: Bool?
    private(set) var busy = false
    private(set) var failure: Failure?
    private(set) var hasAPIKey = false

    @ObservationIgnored private weak var environment: AppEnvironment?
    @ObservationIgnored private(set) var service: Router9Service?
    @ObservationIgnored private var profile: String?
    @ObservationIgnored private var secrets: any SecretStore = KeychainStore.forLaunch()
    @ObservationIgnored private var refreshing: Task<Void, Never>?

    static let installTool = "router9"

    var preferences: Router9Preferences { environment?.preferences?.document.router9Settings ?? Router9Preferences() }
    var hasInstall: Bool { Router9.hasInstall(status) }
    var isRunning: Bool { status?.running == true }
    var resolved: (source: AletheIntegrations.Router9Source, install: Router9Install)? {
        Router9.resolveSource(status, preferred: AletheIntegrations.Router9Source(preferences.source))
    }

    func start(environment: AppEnvironment) {
        self.environment = environment
        guard let locations = environment.locations, let profileID = environment.profileID else { return }
        profile = profileID.rawValue
        service = Router9Service(profileDirectory: locations.profileDirectory(profileID),
                                 dependencies: .live(launchers: environment.launchers))
        loadKeyPresence()
        autoStart()
    }

    func stop() async {
        refreshing?.cancel()
        await service?.stop()
    }

    func refresh() async {
        if let refreshing { return await refreshing.value }
        guard let service, let environment else { return }
        let port = preferences.port, launchers = environment.launchers
        let task = Task {
            async let next = service.status(port: port)
            async let npm = Task.detached { launchers.resolve("npm") != nil }.value
            let (status, hasNPM) = await (next, npm)
            self.status = status
            self.hasNPM = hasNPM
        }
        refreshing = task
        await task.value
        refreshing = nil
    }

    func watch() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let service else { return }
            if service.isRunning != isRunning { await refresh() }
        }
    }

    func toggleRunning() async {
        if isRunning { await stopRouter() } else { await startRouter() }
    }

    func startRouter() async {
        guard let service, !busy else { return }
        busy = true
        failure = nil
        let preferences = preferences
        let source = resolved?.source ?? AletheIntegrations.Router9Source(preferences.source)
        do throws(Router9Error) {
            try await service.start(port: preferences.port, source: source)
        } catch {
            failure = .service(error)
        }
        busy = false
        await refresh()
    }

    func stopRouter() async {
        guard let service, !busy else { return }
        busy = true
        await service.stop()
        busy = false
        await refresh()
    }

    private func autoStart() {
        guard Router9.wantsAutoStart(preferences), let service else { return }
        Task {
            let preferences = preferences
            let status = await service.status(port: preferences.port)
            self.status = status
            guard let source = Router9.autoStartSource(preferences, status: status) else { return }
            do throws(Router9Error) {
                try await service.start(port: preferences.port, source: source)
            } catch {
                failure = .service(error)
            }
            await refresh()
        }
    }

    func update(_ change: (inout Router9Preferences) -> Void) {
        let before = preferences
        environment?.preferences?.update { document in
            var settings = document.router9Settings
            change(&settings)
            document.router9 = settings
        }
        let after = preferences
        if before.enabled, !after.enabled { Task { await stopRouter() } }
        if before.port != after.port { Task { await refresh() } }
    }

    func saveAPIKey(_ value: String) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile, !key.isEmpty else { return }
        writeKey(key, profile: profile)
    }

    func removeAPIKey() {
        guard let profile else { return }
        writeKey("", profile: profile)
    }

    func routingConfig() async -> Router9RoutingConfig? {
        let preferences = preferences
        guard preferences.enabled, let profile else { return nil }
        let secrets = secrets
        let key = await Task.detached { try? secrets.string(for: .router9APIKey, profile: profile) }.value ?? nil
        guard let key, !key.isEmpty else { return nil }
        return Router9RoutingConfig(preferences, apiKey: key)
    }

    private func writeKey(_ key: String, profile: String) {
        let secrets = secrets
        Task {
            let saved = await Task.detached {
                (try? secrets.setString(key, for: .router9APIKey, profile: profile)) != nil
            }.value
            if saved {
                hasAPIKey = !key.isEmpty
                if failure == .keychain { failure = nil }
            } else {
                failure = .keychain
            }
        }
    }

    private func loadKeyPresence() {
        guard let profile else { return }
        let secrets = secrets
        Task {
            hasAPIKey = await Task.detached {
                ((try? secrets.data(for: .router9APIKey, profile: profile)) ?? nil)?.isEmpty == false
            }.value
        }
    }

    enum InstallAction: String, Identifiable {
        case install, uninstall
        var id: Self { self }
    }

    func command(for action: InstallAction) async -> String? {
        guard let service else { return nil }
        if case .install = action {
            do throws(Router9Error) { return try await service.installCommand() } catch {
                failure = .service(error)
                return nil
            }
        } else {
            return service.uninstallCommand()
        }
    }

    func run(_ action: InstallAction, command: String) async {
        guard let environment, let service else { return }
        if action == .uninstall { await service.stop() }
        await environment.installer.run(command: command, tool: Self.installTool) {
            let status = await service.status(port: self.preferences.port)
            return action == .install ? status.managed.installed : !status.managed.installed
        }
        environment.launchers.invalidate()
        await refresh()
    }

    #if DEBUG
    func useStubService(_ dependencies: Router9Dependencies) {
        guard let locations = environment?.locations, let profileID = environment?.profileID else { return }
        service = Router9Service(profileDirectory: locations.profileDirectory(profileID), dependencies: dependencies)
        Task { await refresh() }
    }

    var secretStore: any SecretStore { secrets }
    #endif
}
