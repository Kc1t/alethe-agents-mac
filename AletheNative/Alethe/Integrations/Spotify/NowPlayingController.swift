import AletheFoundation
import AletheIntegrations
import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class NowPlayingController {
    private(set) var model: NowPlayingModel?
    private(set) var hasClientSecret: Bool?
    @ObservationIgnored private weak var environment: AppEnvironment?
    @ObservationIgnored private var secrets: (any SecretStore)?
    @ObservationIgnored private var profile = ""
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func start(environment: AppEnvironment) {
        guard model == nil, let profileID = environment.profileID, let locations = environment.locations else { return }
        self.environment = environment
        let secrets = KeychainStore.forLaunch()
        self.secrets = secrets
        profile = profileID.rawValue
        let service = SpotifyService(profile: profile, secrets: secrets,
                                     dependencies: .live(pages: Self.callbackPages))
        let store = NowPlayingLastTrackStore(
            url: locations.profileDirectory(profileID).appending(path: NowPlayingLastTrackStore.fileName))
        let model = NowPlayingModel(source: service, lastTrack: store)
        model.clientID = { [weak environment] in environment?.preferences?.document.spotifyClientID }
        model.setAppActive(NSApp?.isActive ?? true)
        self.model = model
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak model] _ in
                MainActor.assumeIsolated { model?.setAppActive(true) }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak model] _ in
                MainActor.assumeIsolated { model?.setAppActive(false) }
            },
        ]
        Task { await model.restoreLastTrack() }
    }

    var isConnecting: Bool { model?.connecting ?? false }

    func connect() {
        guard let model, connectTask == nil else { return }
        connectTask = Task { [weak self] in
            await model.connect()
            self?.connectTask = nil
        }
    }

    func cancelConnect() {
        connectTask?.cancel()
    }

    func disconnect() {
        guard let model else { return }
        connectTask?.cancel()
        Task { await model.disconnect() }
    }

    func loadSecretStatus() {
        guard let secrets else { return }
        let profile = profile
        Task {
            let stored = await Task.detached(priority: .utility) {
                ((try? secrets.string(for: .spotifyClientSecret, profile: profile)) ?? nil).map { !$0.isEmpty } ?? false
            }.value
            hasClientSecret = stored
        }
    }

    func setClientSecret(_ value: String) {
        guard let secrets else { return }
        let profile = profile
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                do {
                    if trimmed.isEmpty {
                        try secrets.delete(.spotifyClientSecret, profile: profile)
                    } else {
                        try secrets.setString(trimmed, for: .spotifyClientSecret, profile: profile)
                    }
                    return true
                } catch {
                    AppLog.record(.error, .integrations, "Spotify client secret not saved: \(error)")
                    return false
                }
            }.value
            if ok { hasClientSecret = !trimmed.isEmpty }
        }
    }

    private static var callbackPages: SpotifyCallbackPages {
        SpotifyCallbackPages(
            successTitle: String(localized: "spotify.callback.success.title"),
            successMessage: String(localized: "spotify.callback.success.message"),
            failureTitle: String(localized: "spotify.callback.failure.title"),
            failureMessage: String(localized: "spotify.callback.failure.message"))
    }

    static func message(_ error: SpotifyError) -> String {
        if case .missingCredentials = error {
            return String(localized: "spotify.error.missingCredentials")
        } else if case .loginInProgress = error {
            return String(localized: "spotify.error.loginInProgress")
        } else if case .portBusy = error {
            return String(localized: "spotify.error.portBusy")
        } else if case .browserUnavailable = error {
            return String(localized: "spotify.error.browser")
        } else if case .timedOut = error {
            return String(localized: "spotify.error.timedOut")
        } else if case .cancelled = error {
            return String(localized: "spotify.error.cancelled")
        } else if case .stateMismatch = error {
            return String(localized: "spotify.error.stateMismatch")
        } else if case .authorizationDenied = error {
            return String(localized: "spotify.error.denied")
        } else if case .refreshRejected = error {
            return String(localized: "spotify.error.refreshRejected")
        } else if case .network = error {
            return String(localized: "spotify.error.network")
        } else if case .secretStore = error {
            return String(localized: "spotify.error.keychain")
        } else if case .tokenRequestFailed(let status, _) = error {
            return String(format: String(localized: "spotify.error.status"), status)
        } else if case .requestFailed(let status) = error {
            return String(format: String(localized: "spotify.error.status"), status)
        } else {
            return String(localized: "spotify.error.generic")
        }
    }
}
