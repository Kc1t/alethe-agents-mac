import Foundation
import Network

extension RemoteTransport {
    static func webSocketParameters(allowedOrigin: String, queue: DispatchQueue) -> NWParameters {
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

    func bind(
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
                if case .ready = state {
                    if resumed.claim() { continuation.resume(returning: true) }
                } else if case .failed = state {
                    if resumed.claim() { continuation.resume(returning: false) }
                } else if case .cancelled = state {
                    if resumed.claim() { continuation.resume(returning: false) }
                } else if case .waiting = state {
                    if resumed.claim() { continuation.resume(returning: false) }
                }
            }
            listener.start(queue: queue)
        }
    }

    enum ListenerKind: Sendable {
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
            if case .http = kind {
                await self.serveHTTP(socket, run)
            } else if case .webSocket = kind {
                await self.serveWebSocket(socket, run)
            }
            socket.close()
            self.lock.withLock { _ = run.sockets.removeValue(forKey: key) }
        }
    }
}
