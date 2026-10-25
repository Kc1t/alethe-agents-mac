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

    private final class Run: @unchecked Sendable {
        let generation: UInt64
        var listeners: [NWListener] = []
        var sockets: [ObjectIdentifier: RemoteSocket] = [:]
        var tasks: [Task<Void, Never>] = []

        init(generation: UInt64) {
            self.generation = generation
        }
    }

    public let hub: RemoteHub
    private let router: any RemoteRouter
    private let terminals: any RemoteTerminalSource
    private let workspace: any RemoteWorkspaceSource
    public let configuration: Configuration
    private let queue = DispatchQueue(label: "alethe.remote.transport")
    private let lock = NSLock()
    private var run: Run?

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

    private static func webSocketParameters(allowedOrigin: String, queue: DispatchQueue) -> NWParameters {
        let parameters = NWParameters.tcp
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        options.maximumMessageSize = RemoteLimits.maxMessage
        options.setClientRequestHandler(queue) { _, headers in
            let origin = headers.first { $0.name.caseInsensitiveCompare("Origin") == .orderedSame }?.value
            let allowed = origin == nil || origin == allowedOrigin
            if !allowed { RemoteLog.logger.warning("WebSocket origin refused") }
            return NWProtocolWebSocket.Response(status: allowed ? .accept : .reject, subprotocol: nil, additionalHeaders: nil)
        }
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        return parameters
    }

    private func bind(
        host: String,
        ports: ClosedRange<UInt16>,
        parameters: NWParameters,
        run: Run,
        kind: ListenerKind
    ) async -> (listener: NWListener, port: UInt16)? {
        for port in ports {
            guard !Task.isCancelled, let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
            let parameters = parameters.copy()
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: nwPort)
            parameters.allowLocalEndpointReuse = false
            guard let listener = try? NWListener(using: parameters) else { continue }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return connection.cancel() }
                self.accept(connection, run: run, kind: kind)
            }
            if await ready(listener) {
                let kept = lock.withLock { () -> Bool in
                    guard self.run === run else { return false }
                    run.listeners.append(listener)
                    return true
                }
                guard kept else {
                    listener.cancel()
                    return nil
                }
                return (listener, listener.port?.rawValue ?? port)
            }
            listener.cancel()
        }
        return nil
    }

    private func ready(_ listener: NWListener) async -> Bool {
        let resumed = OnceFlag()
        return await withCheckedContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.claim() { continuation.resume(returning: true) }
                case .failed, .cancelled, .waiting:
                    if resumed.claim() { continuation.resume(returning: false) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private enum ListenerKind: Sendable {
        case http, webSocket
    }

    private func accept(_ connection: NWConnection, run: Run, kind: ListenerKind) {
        let socket = RemoteSocket(connection, queue: queue)
        let key = ObjectIdentifier(socket)
        let registered = lock.withLock { () -> Bool in
            guard self.run === run else { return false }
            run.sockets[key] = socket
            return true
        }
        guard registered else { return connection.cancel() }
        Task { [weak self] in
            guard let self else { return socket.cancel() }
            switch kind {
            case .http: await self.serveHTTP(socket, run)
            case .webSocket: await self.serveWebSocket(socket, run)
            }
            socket.close()
            self.lock.withLock { _ = run.sockets.removeValue(forKey: key) }
        }
    }

    private func serveHTTP(_ socket: RemoteSocket, _ run: Run) async {
        guard await hub.isActive(generation: run.generation),
              await hub.tryAcquireConnection(max: configuration.maxConnections) else {
            return socket.cancel()
        }
        await serveHTTPRequest(socket)
        await hub.releaseConnection()
    }

    private func serveHTTPRequest(_ socket: RemoteSocket) async {
        guard await socket.start(timeout: configuration.socketTimeout) else { return }
        let address = socket.peerAddress
        if await hub.authBlocked(address) {
            await respond(socket, .error(429, "Too many failed attempts"))
            return
        }
        let request: RemoteRequest
        switch await readRequest(socket) {
        case .complete(let head, let body):
            guard let parsed = RemoteHTTPReader.request(head: head, body: body, peerAddress: address) else {
                return await respond(socket, .error(400, "Bad request"))
            }
            request = parsed
        case .failed(let error):
            RemoteLog.logger.info("remote HTTP request refused: \(String(describing: error), privacy: .public)")
            return await respond(socket, .error(400, "Bad request"))
        case .needMore:
            return
        }
        var response = await router.route(request)
        if response.exceedsLimit {
            RemoteLog.logger.error("remote response of \(response.body.count, privacy: .public) bytes over its limit")
            response = .error(400, "Bad request")
        }
        await respond(socket, response)
    }

    private func readRequest(_ socket: RemoteSocket) async -> RemoteHTTPReader.Outcome {
        var reader = RemoteHTTPReader()
        while true {
            guard let (data, complete) = try? await socket.receive(maximumLength: 64 * 1024, timeout: configuration.socketTimeout) else {
                return .needMore
            }
            if let data, !data.isEmpty {
                let outcome = reader.append(data)
                if outcome != .needMore { return outcome }
            }
            if complete { return reader.finish() }
        }
    }

    private func respond(_ socket: RemoteSocket, _ response: RemoteResponse) async {
        try? await socket.send(Data(response.head().utf8) + response.body, timeout: configuration.socketTimeout)
    }

    private func serveWebSocket(_ socket: RemoteSocket, _ run: Run) async {
        guard await hub.isActive(generation: run.generation),
              await hub.tryAcquireConnection(max: configuration.maxConnections) else {
            return socket.cancel()
        }
        let address = socket.peerAddress
        if await hub.authBlocked(address) {
            socket.cancel()
        } else if await socket.start(timeout: configuration.socketTimeout) {
            let session = WebSocketSession(socket: socket, address: address, generation: run.generation)
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.receiveCommands(session) }
                group.addTask { await self.watch(session) }
                await group.next()
                socket.closeWebSocket()
                group.cancelAll()
            }
            session.forwarder?.cancel()
            if let id = session.id { await hub.detach(id) }
        }
        await hub.releaseConnection()
    }

    private final class WebSocketSession: @unchecked Sendable {
        let socket: RemoteSocket
        let address: String
        let generation: UInt64
        let openedAt = ContinuousClock.now
        private let lock = NSLock()
        private var sessionID: Int?
        private var forwardTask: Task<Void, Never>?

        init(socket: RemoteSocket, address: String, generation: UInt64) {
            self.socket = socket
            self.address = address
            self.generation = generation
        }

        var id: Int? {
            get { lock.withLock { sessionID } }
            set { lock.withLock { sessionID = newValue } }
        }

        var forwarder: Task<Void, Never>? {
            get { lock.withLock { forwardTask } }
            set { lock.withLock { forwardTask = newValue } }
        }
    }

    private func receiveCommands(_ session: WebSocketSession) async {
        let socket = session.socket
        while !Task.isCancelled {
            guard let message = try? await socket.receiveMessage() else { return }
            switch message.opcode {
            case .close:
                return
            case .text:
                guard message.data.count <= RemoteLimits.maxMessage else {
                    socket.closeWebSocket(code: .protocolCode(.messageTooBig))
                    return
                }
                guard await handleCommand(message.data, session) else { return }
            default:
                guard message.data.count <= RemoteLimits.maxMessage else {
                    socket.closeWebSocket(code: .protocolCode(.messageTooBig))
                    return
                }
            }
        }
    }

    private func handleCommand(_ data: Data, _ session: WebSocketSession) async -> Bool {
        guard let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return true
        }
        let provided = command["sessionToken"] as? String ?? ""
        let matched = await hub.sessionID(for: provided)
        guard let id = matched, session.id == nil || session.id == id else {
            if session.id == nil { await hub.recordAuthFailure(session.address) }
            await send(RemoteFrame.unauthorized, on: session)
            return false
        }
        if session.id == nil {
            await hub.clearAuthFailures(session.address)
            if let name = command["deviceName"] as? String {
                await hub.renameDevice(id, to: name)
            }
            guard let stream = await hub.attach(id) else {
                await send(RemoteFrame.unauthorized, on: session)
                return false
            }
            session.id = id
            session.forwarder = Task { [weak self] in
                for await frame in stream {
                    guard let self, await self.send(frame, on: session) else { return }
                }
                guard !Task.isCancelled else { return }
                await self?.send(RemoteFrame.expired, on: session)
                session.socket.closeWebSocket()
            }
            RemoteLog.logger.info("device \(id, privacy: .public) connected over WebSocket")
            await send(RemoteFrame.authenticated, on: session)
        }
        if command["type"] as? String == "subscribe" {
            let terminalID = command["ptyId"] as? String
            await subscribe(id, to: terminalID, session)
        }
        return true
    }

    private func subscribe(_ id: Int, to terminalID: String?, _ session: WebSocketSession) async {
        guard let terminalID else {
            await hub.setSubscription(id, terminalID: nil)
            return
        }
        guard await workspace.sharedTab(terminalID) != nil else {
            await hub.setSubscription(id, terminalID: nil)
            return
        }
        await hub.setSubscription(id, terminalID: terminalID)
        let text = await terminals.scrollbackTail(terminalID: terminalID, maxBytes: RemoteLimits.maxScrollback)
        let size = await terminals.size(terminalID: terminalID) ?? .fallback
        await send(RemoteFrame.scrollback(terminalID: terminalID, text: text, size: size), on: session)
    }

    private func watch(_ session: WebSocketSession) async {
        let authDeadline = session.openedAt + configuration.webSocketAuthTimeout
        while !Task.isCancelled {
            let now = ContinuousClock.now
            if session.id == nil {
                if now >= authDeadline { return }
                try? await Task.sleep(for: min(configuration.sessionCheckInterval, authDeadline - now))
                continue
            }
            try? await Task.sleep(for: configuration.sessionCheckInterval)
            guard !Task.isCancelled, await hub.isActive(generation: session.generation) else { return }
            if let id = session.id, await !hub.sessionAlive(id) {
                await send(RemoteFrame.expired, on: session)
                return
            }
        }
    }

    @discardableResult
    private func send(_ frame: String, on session: WebSocketSession) async -> Bool {
        do {
            try await session.socket.sendText(frame, timeout: configuration.socketTimeout)
            return true
        } catch {
            return false
        }
    }
}
