import Foundation
import Network
import Testing
@testable import AletheRemote

let loopback = RemoteHostResolver(lanAddress: { "127.0.0.1" }, tailscaleAddress: { nil })

struct Fixture {
    let hub: RemoteHub
    let router: StubRouter
    let terminals: StubTerminals
    let transport: RemoteTransport

    init(hub: RemoteHub, configuration: RemoteTransport.Configuration) {
        self.hub = hub
        router = StubRouter(hub: hub)
        terminals = StubTerminals()
        transport = RemoteTransport(
            hub: hub, router: router, terminals: terminals, workspace: StubWorkspace(), configuration: configuration
        )
    }

    static func started(configuration: RemoteTransport.Configuration = .standard, clock: TestClock? = nil) async throws -> Fixture {
        let hub = clock.map { clock in RemoteHub(resolver: loopback, now: { clock.now }) } ?? RemoteHub(resolver: loopback)
        let fixture = Fixture(hub: hub, configuration: configuration)
        try #require(await fixture.transport.start())
        return fixture
    }

    func pairDirectly() async throws -> RemotePairing {
        await hub.openPairingWindow()
        return try await hub.pair(token: await hub.pairingToken, name: "Phone", address: "127.0.0.1:1")
    }

    func http(_ request: String) async throws -> String {
        let client = TestTCPClient(port: await hub.httpPort)
        try #require(await client.connect())
        await client.send(Data(request.utf8))
        let data = try #require(await client.readToEnd(timeout: .seconds(10)))
        return String(decoding: data, as: UTF8.self)
    }

    func finish() {
        let transport = transport
        let terminals = terminals
        Task {
            await transport.stop()
            terminals.finish()
        }
    }
}

final class StubRouter: RemoteRouter, @unchecked Sendable {
    let hub: RemoteHub
    private let lock = NSLock()
    private var count = 0

    init(hub: RemoteHub) {
        self.hub = hub
    }

    var calls: Int { lock.withLock { count } }

    func route(_ request: RemoteRequest) async -> RemoteResponse {
        lock.withLock { count += 1 }
        if request.path == "/api/pair" {
            struct Pair: Decodable {
                let token: String
                let deviceName: String?
            }
            guard let payload = try? JSONDecoder().decode(Pair.self, from: request.body) else {
                return .error(400, "Bad request")
            }
            do throws(RemotePairingError) {
                let pairing = try await hub.pair(
                    token: payload.token, name: payload.deviceName ?? "Remote device", address: request.peerAddress
                )
                return .json(200, encoding: ["sessionToken": pairing.sessionToken, "deviceId": String(pairing.deviceID)])
            } catch {
                await hub.recordAuthFailure(request.peerAddress)
                return .error(401, error.message)
            }
        } else if request.path == "/oversized" {
            return .json(200, Data(count: RemoteLimits.maxBody + 1))
        } else {
            return .json(200, encoding: ["method": request.method, "path": request.path])
        }
    }
}

final class StubTerminals: RemoteTerminalSource, @unchecked Sendable {
    static let scrollback = "$ echo hello\r\nhello\r\n"
    private let stream: AsyncStream<RemoteTerminalOutput>
    private let continuation: AsyncStream<RemoteTerminalOutput>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: RemoteTerminalOutput.self)
    }

    func emit(_ output: RemoteTerminalOutput) {
        continuation.yield(output)
    }

    func finish() {
        continuation.finish()
    }

    func scrollbackTail(terminalID: String, maxBytes: Int) async -> String { Self.scrollback }
    func size(terminalID: String) async -> RemoteTerminalSize? { RemoteTerminalSize(cols: 120, rows: 40) }
    func write(terminalID: String, text: String) async throws(RemoteInputError) {}
    func output() -> AsyncStream<RemoteTerminalOutput> { stream }
}

private struct StubWorkspace: RemoteWorkspaceSource {
    func sharedTabs() async -> [RemoteSharedTab] {
        [RemoteSharedTab(terminalID: "pty-1", agent: "shell", cwd: "/tmp", sessionID: nil)]
    }

    func snapshot() async -> RemoteWorkspaceSnapshot { RemoteWorkspaceSnapshot(groups: [], projects: []) }

    func appearance() async -> RemoteAppearance {
        RemoteAppearance(uiTheme: "elite-indigo", appIconTheme: "default", language: "en", motionPreference: "system", colorScheme: "dark")
    }

    func transcript(for tab: RemoteSharedTab, since: UInt64?, limit: Int) async throws -> RemoteTranscript {
        RemoteTranscript(sessionId: nil, revision: 0, unchanged: true, messages: [])
    }

    func activeQuestions(for tab: RemoteSharedTab) async -> RemoteQuestionSet? { nil }
}

func nextEvent(_ hub: RemoteHub, timeout: Duration = .seconds(5)) async -> RemoteEvent? {
    await withTaskGroup(of: RemoteEvent?.self) { group in
        group.addTask {
            var iterator = hub.events.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

func eventually(timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}
