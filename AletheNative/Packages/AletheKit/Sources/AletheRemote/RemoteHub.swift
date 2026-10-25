import Foundation

public struct RemoteDeviceInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var address: String
    public var connectedAt: Date
    public var expiresAt: Date
    public var online: Bool
}

public struct RemoteInfo: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var connectedDevices: Int
    public var onlineDevices: Int
    public var maxDevices: Int
    public var sessionExpirySecs: Int
    public var readOnly: Bool
    public var allowShellInput: Bool
    public var reachMode: RemoteReachMode
    public var pairingOpen: Bool
    public var pairingExpiresIn: Int
    public var devices: [RemoteDeviceInfo]
    public var pairingURL: String?
    public var httpURL: String?
    public var wsURL: String?
}

public struct RemotePairing: Equatable, Sendable {
    public var deviceID: Int
    public var sessionToken: String
}

public enum RemotePairingError: Error, Equatable, Sendable {
    case windowClosed, invalidToken, deviceLimitReached

    public var message: String {
        if self == .windowClosed { return "Pairing window is closed" }
        if self == .invalidToken { return "Invalid pairing token" }
        return "Maximum remote devices reached"
    }
}

public actor RemoteHub {
    public typealias Clock = @Sendable () -> Date

    private struct Session {
        var id: Int
        var token: String
        var name: String
        var address: String
        var connectedAt: Date
        var expiresAt: Date
        var subscription: String?
        var outbox: AsyncStream<String>.Continuation?
    }

    private struct AuthFailures {
        var count: Int
        var windowStart: Date
        var lockedUntil: Date?
    }

    private struct MessageRate {
        var count: Int
        var windowStart: Date
    }

    private let resolver: RemoteHostResolver
    private let clock: Clock

    private(set) var pairingToken = RemoteText.randomToken(length: RemoteLimits.pairingTokenLength)
    private var pairingUntil: Date?
    public private(set) var host = ""
    private var running = false
    public private(set) var generation: UInt64 = 0
    public private(set) var httpPort: UInt16 = 0
    public private(set) var wsPort: UInt16 = 0
    private var nextSessionID = 1
    public private(set) var maxDevices = 1
    public private(set) var sessionExpiry = RemoteLimits.defaultSessionExpiry
    public private(set) var isReadOnly = false
    public private(set) var shellInputAllowed = false
    public private(set) var reachMode = RemoteReachMode.lan
    private(set) var connections = 0
    private var sessions: [Session] = []
    private var failures: [String: AuthFailures] = [:]
    private var messageRates: [Int: MessageRate] = [:]
    private var lastActive: Date

    public nonisolated let events: AsyncStream<RemoteEvent>
    private nonisolated let eventSink: AsyncStream<RemoteEvent>.Continuation

    public init(resolver: RemoteHostResolver = .system, now: @escaping Clock = { Date() }) {
        self.resolver = resolver
        self.clock = now
        self.lastActive = now()
        let (stream, continuation) = AsyncStream.makeStream(of: RemoteEvent.self)
        events = stream
        eventSink = continuation
    }

    public nonisolated func emit(_ event: RemoteEvent) {
        eventSink.yield(event)
    }

    public var isEnabled: Bool { running }

    public func isActive(generation: UInt64) -> Bool {
        running && self.generation == generation
    }

    @discardableResult
    public func beginRun() -> Bool {
        defer { running = true }
        return running
    }

    public func endRun() {
        running = false
    }

    @discardableResult
    public func nextGeneration() -> UInt64 {
        generation += 1
        return generation
    }

    public func start() async -> UInt64? {
        guard !beginRun() else { return nil }
        await refreshHost()
        touchActivity()
        return nextGeneration()
    }

    public func stop() {
        endRun()
        nextGeneration()
        resetPorts()
        revokeAll()
        closePairingWindow()
        RemoteLog.logger.info("remote control disabled")
    }

    public func setHTTPPort(_ port: UInt16) { httpPort = port }
    public func setWSPort(_ port: UInt16) { wsPort = port }

    public func clearHTTPPort(ifGeneration generation: UInt64) {
        if self.generation == generation { httpPort = 0 }
    }

    public func clearWSPort(ifGeneration generation: UInt64) {
        if self.generation == generation { wsPort = 0 }
    }

    public func resetPorts() {
        httpPort = 0
        wsPort = 0
    }

    public func setMaxDevices(_ value: Int) {
        maxDevices = min(max(value, RemoteLimits.deviceRange.lowerBound), RemoteLimits.deviceRange.upperBound)
    }

    public func setSessionExpiry(_ seconds: TimeInterval) {
        sessionExpiry = min(max(seconds, RemoteLimits.sessionExpiryRange.lowerBound), RemoteLimits.sessionExpiryRange.upperBound)
    }

    public func setReadOnly(_ value: Bool) { isReadOnly = value }
    public func setAllowShellInput(_ value: Bool) { shellInputAllowed = value }

    @discardableResult
    public func setReachMode(_ mode: RemoteReachMode) -> Bool {
        defer { reachMode = mode }
        return reachMode != mode
    }

    public func tryAcquireConnection(max: Int = RemoteLimits.maxConnections) -> Bool {
        guard connections < max else { return false }
        connections += 1
        return true
    }

    public func releaseConnection() {
        connections = Swift.max(0, connections - 1)
    }

    public func refreshHost() async {
        host = await resolver.host(for: reachMode)
    }

    public func openPairingWindow() {
        pairingToken = RemoteText.randomToken(length: RemoteLimits.pairingTokenLength)
        pairingUntil = clock().addingTimeInterval(RemoteLimits.pairingWindow)
    }

    public func closePairingWindow() {
        pairingToken = RemoteText.randomToken(length: RemoteLimits.pairingTokenLength)
        pairingUntil = nil
    }

    public var pairingRemaining: Int {
        guard running, let pairingUntil else { return 0 }
        return Swift.max(0, Int(pairingUntil.timeIntervalSince(clock())))
    }

    public var pairingURL: String? {
        guard pairingRemaining > 0, httpPort != 0 else { return nil }
        return "http://\(host):\(httpPort)/?pair=\(pairingToken)"
    }

    public func pair(token provided: String, name: String, address: String) throws(RemotePairingError) -> RemotePairing {
        guard pairingRemaining > 0 else { throw .windowClosed }
        guard RemoteText.tokensEqual(provided, pairingToken) else { throw .invalidToken }
        pruneExpired()
        guard sessions.count < maxDevices else { throw .deviceLimitReached }
        let id = nextSessionID
        nextSessionID += 1
        let token = RemoteText.randomToken(length: RemoteLimits.sessionTokenLength)
        let connectedAt = clock()
        sessions.append(Session(
            id: id,
            token: token,
            name: RemoteText.truncated(name, to: RemoteLimits.maxDeviceName),
            address: address,
            connectedAt: connectedAt,
            expiresAt: connectedAt.addingTimeInterval(sessionExpiry),
            subscription: nil,
            outbox: nil
        ))
        closePairingWindow()
        touchActivity()
        RemoteLog.logger.info("device \(id, privacy: .public) paired from \(address, privacy: .private)")
        return RemotePairing(deviceID: id, sessionToken: token)
    }

    public func info() -> RemoteInfo {
        pruneExpired()
        let devices = sessions.map {
            RemoteDeviceInfo(
                id: $0.id, name: $0.name, address: $0.address,
                connectedAt: $0.connectedAt, expiresAt: $0.expiresAt, online: $0.outbox != nil
            )
        }
        let pairingURL = pairingURL
        return RemoteInfo(
            enabled: running,
            connectedDevices: devices.count,
            onlineDevices: devices.filter(\.online).count,
            maxDevices: maxDevices,
            sessionExpirySecs: Int(sessionExpiry),
            readOnly: isReadOnly,
            allowShellInput: shellInputAllowed,
            reachMode: reachMode,
            pairingOpen: pairingURL != nil,
            pairingExpiresIn: pairingRemaining,
            devices: devices,
            pairingURL: pairingURL,
            httpURL: httpPort != 0 ? "http://\(host):\(httpPort)" : nil,
            wsURL: wsPort != 0 ? "ws://\(host):\(wsPort)" : nil
        )
    }

    public var allowedOrigin: String { "http://\(host):\(httpPort)" }

    public func connectedDeviceCount() -> Int {
        guard running else { return 0 }
        pruneExpired()
        return sessions.count
    }

    public func pruneExpired() {
        let now = clock()
        sessions.removeAll { session in
            guard session.expiresAt <= now else { return false }
            session.outbox?.finish()
            messageRates[session.id] = nil
            return true
        }
    }

    public func sessionID(for token: String) -> Int? {
        guard !token.isEmpty else { return nil }
        pruneExpired()
        var match: Int?
        for session in sessions where RemoteText.tokensEqual(token, session.token) && match == nil {
            match = session.id
        }
        return match
    }

    public func sessionAlive(_ id: Int) -> Bool {
        let now = clock()
        return sessions.contains { $0.id == id && $0.expiresAt > now }
    }

    public func deviceName(_ id: Int) -> String {
        sessions.first { $0.id == id }?.name ?? "Remote device"
    }

    public func renameDevice(_ id: Int, to name: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].name = RemoteText.truncated(name, to: RemoteLimits.maxDeviceName)
    }

    public func attach(_ id: Int) -> AsyncStream<String>? {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return nil }
        sessions[index].outbox?.finish()
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        sessions[index].outbox = continuation
        return stream
    }

    public func detach(_ id: Int) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].outbox?.finish()
        sessions[index].outbox = nil
        sessions[index].subscription = nil
    }

    public func setSubscription(_ id: Int, terminalID: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].subscription = terminalID
    }

    public func subscription(_ id: Int) -> String? {
        sessions.first { $0.id == id }?.subscription
    }

    @discardableResult
    public func publish(terminalID: String, payload: @Sendable () -> String) -> Int {
        let now = clock()
        let subscribed = sessions.indices.filter {
            sessions[$0].expiresAt > now && sessions[$0].outbox != nil && sessions[$0].subscription == terminalID
        }
        guard !subscribed.isEmpty else { return 0 }
        let message = payload()
        var delivered = 0
        for index in subscribed {
            guard let outbox = sessions[index].outbox else { continue }
            if case .terminated = outbox.yield(message) {
                sessions[index].outbox = nil
            } else {
                delivered += 1
            }
        }
        return delivered
    }

    public func publish(_ output: RemoteTerminalOutput) {
        publish(terminalID: output.terminalID) { output.frame }
    }

    public func revokeDevice(_ id: Int) {
        sessions.removeAll { session in
            guard session.id == id else { return false }
            session.outbox?.finish()
            return true
        }
        messageRates[id] = nil
        RemoteLog.logger.info("device \(id, privacy: .public) revoked")
    }

    public func revokeAll() {
        for session in sessions { session.outbox?.finish() }
        sessions.removeAll()
        messageRates.removeAll()
    }

    public func touchActivity() {
        lastActive = clock()
    }

    public func isIdle(threshold: TimeInterval = RemoteLimits.idleDisable) -> Bool {
        connectedDeviceCount() == 0
            && Self.idleExpired(now: clock().timeIntervalSince1970, lastActive: lastActive.timeIntervalSince1970, threshold: threshold)
    }

    static func idleExpired(now: TimeInterval, lastActive: TimeInterval, threshold: TimeInterval) -> Bool {
        threshold > 0 && Swift.max(0, now - lastActive) >= threshold
    }

    public func allowMessage(_ sessionID: Int) -> Bool {
        let now = clock()
        var rate = messageRates[sessionID] ?? MessageRate(count: 0, windowStart: now)
        if now.timeIntervalSince(rate.windowStart) > RemoteLimits.messageRateWindow {
            rate = MessageRate(count: 0, windowStart: now)
        }
        rate.count += 1
        messageRates[sessionID] = rate
        return rate.count <= RemoteLimits.messageRateLimit
    }

    public func authBlocked(_ address: String) -> Bool {
        guard let ip = RemoteHost.peerIP(address), let lockedUntil = failures[ip]?.lockedUntil else { return false }
        return lockedUntil > clock()
    }

    public func recordAuthFailure(_ address: String) {
        guard let ip = RemoteHost.peerIP(address) else { return }
        let now = clock()
        failures = failures.filter { _, entry in
            (entry.lockedUntil.map { $0 > now } ?? false)
                || now.timeIntervalSince(entry.windowStart) <= RemoteLimits.authFailureWindow
        }
        var entry = failures[ip] ?? AuthFailures(count: 0, windowStart: now, lockedUntil: nil)
        if now.timeIntervalSince(entry.windowStart) > RemoteLimits.authFailureWindow {
            entry = AuthFailures(count: 0, windowStart: now, lockedUntil: nil)
        }
        entry.count += 1
        if entry.count >= RemoteLimits.authFailureLimit {
            entry.lockedUntil = now.addingTimeInterval(RemoteLimits.authLockout)
            RemoteLog.logger.warning("too many failed attempts from \(ip, privacy: .private); blocked for 5 minutes")
        }
        failures[ip] = entry
    }

    public func clearAuthFailures(_ address: String) {
        guard let ip = RemoteHost.peerIP(address) else { return }
        failures[ip] = nil
    }
}
