import Foundation
import Network

extension RemoteTransport {
    func serveWebSocket(_ socket: RemoteSocket, _ run: Run) async {
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
            if message.opcode == .close { return }
            guard message.data.count <= RemoteLimits.maxMessage else {
                socket.closeWebSocket(code: .protocolCode(.messageTooBig))
                return
            }
            if message.opcode == .text {
                guard await handleCommand(message.data, session) else { return }
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
