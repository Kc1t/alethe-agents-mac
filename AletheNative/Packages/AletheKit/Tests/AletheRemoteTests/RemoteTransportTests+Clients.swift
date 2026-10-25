@testable import AletheRemote
import Foundation
import Network
import Testing

private func callback<Value: Sendable>(
    timeout: Duration,
    fallback: Value,
    onTimeout: @escaping @Sendable () -> Void,
    _ body: (@escaping @Sendable (Value) -> Void) -> Void
) async -> Value {
    await withCheckedContinuation { continuation in
        let once = OnceFlag()
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) {
            if once.claim() {
                onTimeout()
                continuation.resume(returning: fallback)
            }
        }
        body { value in
            if once.claim() { continuation.resume(returning: value) }
        }
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    var value: Data { lock.withLock { data } }
}

final class TestTCPClient: @unchecked Sendable {
    let connection: NWConnection

    init(port: UInt16) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            preconditionFailure("Invalid test TCP port")
        }
        connection = NWConnection(host: "127.0.0.1", port: endpointPort, using: .tcp)
    }

    func connect() async -> Bool {
        let connection = connection
        return await callback(timeout: .seconds(5), fallback: false, onTimeout: { connection.cancel() }) { done in
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    done(true)
                } else if case .failed = state {
                    done(false)
                } else if case .cancelled = state {
                    done(false)
                } else if case .waiting = state {
                    done(false)
                }
            }
            connection.start(queue: .global())
        }
    }

    func send(_ data: Data) async {
        let connection = connection
        await callback(timeout: .seconds(5), fallback: (), onTimeout: {}) { done in
            connection.send(content: data, completion: .contentProcessed { _ in done(()) })
        }
    }

    func readToEnd(timeout: Duration) async -> Data? {
        let connection = connection
        let buffer = LockedData()
        return await callback(timeout: timeout, fallback: nil, onTimeout: { connection.cancel() }) { done in
            self.receive(into: buffer, done: done)
        }
    }

    private func receive(into buffer: LockedData, done: @escaping @Sendable (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, complete, error in
            if let data { buffer.append(data) }
            if complete || error != nil {
                done(buffer.value)
            } else {
                self.receive(into: buffer, done: done)
            }
        }
    }

    func cancel() { connection.cancel() }
}

enum TestFrame: Equatable {
    case text(String)
    case closed
    case timedOut

    var object: [String: Any]? {
        guard case .text(let text) = self else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}

final class TestWebSocketClient: @unchecked Sendable {
    let connection: NWConnection

    init(port: UInt16, origin: String?) {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        if let origin { options.setAdditionalHeaders([("Origin", origin)]) }
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        guard let url = URL(string: "ws://127.0.0.1:\(port)/") else {
            preconditionFailure("Invalid test WebSocket URL")
        }
        connection = NWConnection(to: .url(url), using: parameters)
    }

    func connect() async -> Bool {
        let connection = connection
        return await callback(timeout: .seconds(5), fallback: false, onTimeout: { connection.cancel() }) { done in
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    done(true)
                } else if case .failed = state {
                    done(false)
                } else if case .cancelled = state {
                    done(false)
                } else if case .waiting = state {
                    done(false)
                }
            }
            connection.start(queue: .global())
        }
    }

    func send(_ text: String) async {
        let connection = connection
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        await callback(timeout: .seconds(5), fallback: (), onTimeout: {}) { done in
            connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .contentProcessed { _ in
                done(())
            })
        }
    }

    func receive(timeout: Duration = .seconds(5)) async -> TestFrame {
        let connection = connection
        return await callback(timeout: timeout, fallback: .timedOut, onTimeout: { connection.cancel() }) { done in
            self.receiveFrame(done)
        }
    }

    private func receiveFrame(_ done: @escaping @Sendable (TestFrame) -> Void) {
        connection.receiveMessage { data, context, _, error in
            guard error == nil,
                  let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            else { return done(.closed) }
            if case .text = metadata.opcode {
                done(.text(String(decoding: data ?? Data(), as: UTF8.self)))
            } else if case .close = metadata.opcode {
                done(.closed)
            } else {
                self.receiveFrame(done)
            }
        }
    }

    func receiveUntilClosed(timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let message = await receive(timeout: deadline - ContinuousClock.now)
            if case .closed = message {
                return true
            } else if case .timedOut = message {
                return false
            } else if case .text = message {
                continue
            }
        }
        return false
    }

    func cancel() { connection.cancel() }
}

final class TestListener: @unchecked Sendable {
    let listener: NWListener
    let port: UInt16

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func bound() async -> TestListener? {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        guard let listener = try? NWListener(using: parameters) else { return nil }
        listener.newConnectionHandler = { $0.cancel() }
        let ready = await callback(timeout: .seconds(5), fallback: false, onTimeout: { listener.cancel() }) { done in
            listener.stateUpdateHandler = { state in
                if case .ready = state {
                    done(true)
                } else if case .failed = state {
                    done(false)
                } else if case .cancelled = state {
                    done(false)
                } else if case .waiting = state {
                    done(false)
                }
            }
            listener.start(queue: .global())
        }
        guard ready, let port = listener.port?.rawValue else { return nil }
        return TestListener(listener: listener, port: port)
    }

    func cancel() { listener.cancel() }
}
