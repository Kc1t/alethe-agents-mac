import Foundation
import Observation

public protocol NowPlayingSource: Sendable {
    func isConnected() async -> Bool
    func login(clientID: String?) async throws(SpotifyError)
    func logout() async throws(SpotifyError)
    func current(clientID: String?) async throws(SpotifyError) -> SpotifyNowPlaying?
}

extension SpotifyService: NowPlayingSource {}

public actor NowPlayingLastTrackStore {
    public static let fileName = "spotify-last-track.json"
    public nonisolated let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> SpotifyNowPlaying? {
        guard let data = try? Data(contentsOf: url),
              var track = try? JSONDecoder().decode(SpotifyNowPlaying.self, from: data),
              !track.track.isEmpty else { return nil }
        track.playing = false
        return track
    }

    public func save(_ track: SpotifyNowPlaying) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(track).write(to: url, options: .atomic)
        } catch {
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

@Observable
@MainActor
public final class NowPlayingModel {
    public static let pollInterval: Duration = .seconds(8)

    public private(set) var connected: Bool?
    public private(set) var current: SpotifyNowPlaying?
    public private(set) var fetchedAt: Date?
    public private(set) var error: SpotifyError?
    public private(set) var connecting = false
    public var isPolling: Bool { pollTask != nil }

    @ObservationIgnored public var clientID: @MainActor () -> String? = { nil }
    @ObservationIgnored public private(set) var source: any NowPlayingSource
    @ObservationIgnored private let lastTrack: NowPlayingLastTrackStore?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var visibleViews = 0
    @ObservationIgnored private var appActive = true
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var stoppedPollTask: Task<Void, Never>?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var statusChecked = false
    @ObservationIgnored private var generation = 0

    public init(source: any NowPlayingSource, lastTrack: NowPlayingLastTrackStore?,
                interval: Duration = NowPlayingModel.pollInterval, now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.lastTrack = lastTrack
        self.interval = interval
        self.now = now
    }

    public func restoreLastTrack() async {
        guard let restored = await lastTrack?.load(), current == nil else { return }
        current = restored
        fetchedAt = nil
    }

    public func replaceSource(_ source: any NowPlayingSource) {
        generation += 1
        self.source = source
        statusChecked = false
        connected = nil
        stopPolling()
        if visibleViews > 0 { Task { await checkStatus() } }
    }

    public func viewAppeared() {
        visibleViews += 1
        if !statusChecked {
            Task { await checkStatus() }
        }
        updatePolling()
    }

    public func viewDisappeared() {
        visibleViews = max(0, visibleViews - 1)
        updatePolling()
    }

    public func setAppActive(_ active: Bool) {
        appActive = active
        updatePolling()
    }

    public func checkStatus() async {
        guard !statusChecked else { return }
        statusChecked = true
        let generation = generation
        let ok = await source.isConnected()
        guard generation == self.generation else { return }
        connected = ok
        updatePolling()
    }

    private var shouldPoll: Bool { connected == true && visibleViews > 0 && appActive }

    private func updatePolling() {
        if shouldPoll {
            guard pollTask == nil else { return }
            let interval = interval
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    try? await Task.sleep(for: interval)
                }
            }
        } else {
            stopPolling()
        }
    }

    private func stopPolling() {
        guard let pollTask else { return }
        pollTask.cancel()
        stoppedPollTask = pollTask
        self.pollTask = nil
    }

    func pollingStopped() async {
        await stoppedPollTask?.value
    }

    public func refresh() async {
        guard connected == true, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        let generation = generation
        do throws(SpotifyError) {
            let track = try await source.current(clientID: clientID())
            guard generation == self.generation else { return }
            if let track {
                let changed = current.map { !$0.sameTrack(as: track) } ?? true
                current = track
                fetchedAt = now()
                if changed, let lastTrack { Task { await lastTrack.save(track) } }
            } else if current?.playing == true {
                current?.playing = false
            }
            error = nil
        } catch .cancelled {
            return
        } catch .refreshRejected {
            guard generation == self.generation else { return }
            connected = false
            error = .refreshRejected
            stopPolling()
        } catch {
            guard generation == self.generation else { return }
            self.error = error
        }
    }

    public func connect() async {
        guard !connecting else { return }
        connecting = true
        error = nil
        defer { connecting = false }
        let generation = generation
        do throws(SpotifyError) {
            try await source.login(clientID: clientID())
            guard generation == self.generation else { return }
            statusChecked = true
            connected = true
            updatePolling()
            if pollTask == nil { await refresh() }
        } catch .cancelled {
            return
        } catch {
            guard generation == self.generation else { return }
            connected = false
            self.error = error
        }
    }

    public func disconnect() async {
        generation += 1
        stopPolling()
        do throws(SpotifyError) {
            try await source.logout()
        } catch {
            self.error = error
            return
        }
        statusChecked = true
        connected = false
        current = nil
        fetchedAt = nil
        error = nil
        await lastTrack?.clear()
    }

    public func progressMs(at date: Date) -> Int {
        guard let current else { return 0 }
        guard current.playing, let fetchedAt else { return current.progressMs }
        let advanced = current.progressMs + Int(max(0, date.timeIntervalSince(fetchedAt)) * 1000)
        return current.durationMs > 0 ? min(advanced, current.durationMs) : advanced
    }
}

extension SpotifyNowPlaying {
    func sameTrack(as other: SpotifyNowPlaying) -> Bool {
        track == other.track && artist == other.artist && album == other.album && trackURL == other.trackURL
            && coverURL == other.coverURL
    }
}
