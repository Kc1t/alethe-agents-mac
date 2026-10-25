import Foundation
import Network

public final class RemoteTransport: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var httpPorts: ClosedRange<UInt16>
        public var webSocketPorts: ClosedRange<UInt16>
        public var maxConnections: Int
        public var socketTimeout: Duration
        public var webSocketAuthTimeout: Duration
        public var idleThreshold: TimeInterval
        public var idleCheckInterval: Duration
        public var sessionCheckInterval: Duration

        public init(
            httpPorts: ClosedRange<UInt16> = RemoteLimits.httpPorts,
            webSocketPorts: ClosedRange<UInt16> = RemoteLimits.webSocketPorts,
            maxConnections: Int = RemoteLimits.maxConnections,
            socketTimeout: Duration = RemoteLimits.socketTimeout,
            webSocketAuthTimeout: Duration = RemoteLimits.webSocketAuthTimeout,
            idleThreshold: TimeInterval = RemoteLimits.idleDisable,
            idleCheckInterval: Duration = .seconds(30),
            sessionCheckInterval: Duration = .seconds(1)
        ) {
            self.httpPorts = httpPorts
            self.webSocketPorts = webSocketPorts
            self.maxConnections = maxConnections
            self.socketTimeout = socketTimeout
            self.webSocketAuthTimeout = webSocketAuthTimeout
            self.idleThreshold = idleThreshold
            self.idleCheckInterval = idleCheckInterval
            self.sessionCheckInterval = sessionCheckInterval
        }

        public static let standard = Configuration()
    }

    final class Run: @unchecked Sendable {
        let generation: UInt64
        var listeners: [NWListener] = []
        var sockets: [ObjectIdentifier: RemoteSocket] = [:]
        var tasks: [Task<Void, Never>] = []

        init(generation: UInt64) {
            self.generation = generation
        }
    }

    public let hub: RemoteHub
    let router: any RemoteRouter
    let terminals: any RemoteTerminalSource
    let workspace: any RemoteWorkspaceSource
    public let configuration: Configuration
    let queue = DispatchQueue(label: "alethe.remote.transport")
    let lock = NSLock()
    var run: Run?

    public init(
        hub: RemoteHub,
        router: any RemoteRouter,
        terminals: any RemoteTerminalSource,
        workspace: any RemoteWorkspaceSource,
        configuration: Configuration = .standard
    ) {
        self.hub = hub
        self.router = router
        self.terminals = terminals
        self.workspace = workspace
        self.configuration = configuration
    }

    public var isRunning: Bool { lock.withLock { run != nil } }

    @discardableResult
    public func start() async -> Bool {
        guard let generation = await hub.start() else { return isRunning }
        let run = Run(generation: generation)
        lock.withLock { self.run = run }

        let host = await hub.host
        guard let bindHost = Self.bindableHost(host) else {
            RemoteLog.logger.error("no bindable host for remote control")
            await failStart(run)
            return false
        }
        guard let http = await bind(host: bindHost, ports: configuration.httpPorts, parameters: .tcp, run: run, kind: .http) else {
            RemoteLog.logger.error("unable to bind the remote HTTP listener")
            await failStart(run)
            return false
        }
        await hub.setHTTPPort(http.port)
        RemoteLog.logger.info("remote HTTP listener on port \(http.port, privacy: .public)")

        let origin = await hub.allowedOrigin
        guard let ws = await bind(
            host: bindHost, ports: configuration.webSocketPorts,
            parameters: Self.webSocketParameters(allowedOrigin: origin, queue: queue),
            run: run, kind: .webSocket
        ) else {
            RemoteLog.logger.error("unable to bind the remote WebSocket listener")
            await failStart(run)
            return false
        }
        await hub.setWSPort(ws.port)
        RemoteLog.logger.info("remote WebSocket listener on port \(ws.port, privacy: .public)")

        guard await hub.isActive(generation: generation) else {
            teardown(run)
            return false
        }
        let terminals = terminals
        let hub = hub
        let pump = Task {
            for await output in terminals.output() {
                if Task.isCancelled { break }
                await hub.publish(output)
            }
        }
        let watch = Task { [weak self] in _ = await self?.watchIdle(run) }
        lock.withLock {
            run.tasks.append(pump)
            run.tasks.append(watch)
        }
        return true
    }

    public func stop() async {
        await hub.stop()
        if let run = lock.withLock({ run }) { teardown(run) }
    }

    private func failStart(_ run: Run) async {
        hub.emit(.startFailed)
        await hub.stop()
        teardown(run)
    }

    private func teardown(_ run: Run) {
        let (listeners, sockets, tasks) = lock.withLock { () -> ([NWListener], [RemoteSocket], [Task<Void, Never>]) in
            if self.run === run { self.run = nil }
            defer {
                run.listeners.removeAll()
                run.sockets.removeAll()
                run.tasks.removeAll()
            }
            return (run.listeners, Array(run.sockets.values), run.tasks)
        }
        listeners.forEach { $0.cancel() }
        sockets.forEach { $0.cancel() }
        tasks.forEach { $0.cancel() }
    }

    private func watchIdle(_ run: Run) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: configuration.idleCheckInterval)
            guard !Task.isCancelled else { return }
            guard await hub.isActive(generation: run.generation) else {
                teardown(run)
                return
            }
            if await hub.isIdle(threshold: configuration.idleThreshold) {
                RemoteLog.logger.info("remote control auto-disabled: no paired device")
                hub.emit(.autoDisabled)
                await hub.stop()
                teardown(run)
                return
            }
        }
    }

    static func bindableHost(_ host: String) -> String? {
        guard let ip = RemoteHost.normalizedIP(host), ip != "0.0.0.0", ip != "::" else { return nil }
        return ip
    }
}
