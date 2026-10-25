@testable import AletheRemote
import Foundation
import Network
import Testing

struct RemoteHTTPGoldenTests {
    @Test func requestHeadersEndIsDetectedAcrossChunks() {
        #expect(RemoteHTTPReader.findHeadersEnd(Data("GET / HTTP/1.1\r\n\r\nbody".utf8)) == 14)
        #expect(RemoteHTTPReader.findHeadersEnd(Data("GET / HTTP/1.1\r\n".utf8)) == nil)
    }

    @Test func headerLookupIsCaseInsensitive() {
        let head = "POST /api/pair HTTP/1.1\r\nContent-Length: 42\r\nAuthorization: Bearer abc"

        #expect(RemoteHTTPReader.headerValue(head, "content-length") == "42")
        #expect(RemoteHTTPReader.bearerToken(head) == "abc")
    }
}

struct RemoteHTTPReaderTests {
    @Test func aSeparatorSplitAcrossChunksCompletesTheRequest() {
        var reader = RemoteHTTPReader()

        #expect(reader.append(Data("GET /a HTTP/1.1\r\nHost: x\r".utf8)) == .needMore)
        #expect(reader.append(Data("\n\r".utf8)) == .needMore)
        #expect(reader.append(Data("\n".utf8)) == .complete(head: "GET /a HTTP/1.1\r\nHost: x", body: Data()))
    }

    @Test func theBodyIsReadUpToContentLength() {
        var reader = RemoteHTTPReader()

        #expect(reader.append(Data("POST /p HTTP/1.1\r\nContent-Length: 5\r\n\r\nhel".utf8)) == .needMore)
        #expect(reader.append(Data("loEXTRA".utf8)) == .complete(head: "POST /p HTTP/1.1\r\nContent-Length: 5", body: Data("hello".utf8)))
    }

    @Test func headersOverTheLimitAreRefused() {
        var reader = RemoteHTTPReader()
        let chunk = Data(repeating: UInt8(ascii: "a"), count: 32 * 1024)

        var outcome = RemoteHTTPReader.Outcome.needMore
        for _ in 0..<4 where outcome == .needMore {
            outcome = reader.append(chunk)
        }

        #expect(outcome == .failed(.headersTooLarge))
    }

    @Test func headersEndingPastTheLimitAreRefused() {
        var reader = RemoteHTTPReader()
        let head = "GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: RemoteLimits.maxRequestHead) + "\r\n\r\n"

        #expect(reader.append(Data(head.utf8)) == .failed(.headersTooLarge))
    }

    @Test func aBodyOverTheLimitIsRefusedBeforeItIsRead() {
        var reader = RemoteHTTPReader()
        let head = "POST /api/message HTTP/1.1\r\nContent-Length: \(RemoteLimits.maxBody + 1)\r\n\r\n"

        #expect(reader.append(Data(head.utf8)) == .failed(.bodyTooLarge))
    }

    @Test func aBodyAtTheLimitIsAccepted() {
        var reader = RemoteHTTPReader()
        let head = "POST /api/message HTTP/1.1\r\nContent-Length: \(RemoteLimits.maxBody)\r\n\r\n"

        #expect(reader.append(Data(head.utf8)) == .needMore)
        guard case .complete(_, let body) = reader.append(Data(count: RemoteLimits.maxBody)) else {
            Issue.record("expected a complete request")
            return
        }
        #expect(body.count == RemoteLimits.maxBody)
    }

    @Test func aPeerClosingEarlyFails() {
        var reader = RemoteHTTPReader()
        _ = reader.append(Data("GET / HTTP/1.1\r\n".utf8))

        #expect(reader.finish() == .failed(.closedEarly))
    }

    @Test func requestLineAndHeadersBecomeARemoteRequest() throws {
        let head = "POST /api/message?x=1 HTTP/1.1\r\nAuthorization: Bearer tok\r\nX-A: first\r\nx-a: second"

        let request = try #require(RemoteHTTPReader.request(head: head, body: Data("{}".utf8), peerAddress: "127.0.0.1:5"))

        #expect(request.method == "POST")
        #expect(request.path == "/api/message")
        #expect(request.bearerToken == "tok")
        #expect(request.header("X-A") == "first")
        #expect(request.peerAddress == "127.0.0.1:5")
    }

    @Test func onlyLiteralNonWildcardHostsAreBindable() {
        #expect(RemoteTransport.bindableHost("") == nil)
        #expect(RemoteTransport.bindableHost("0.0.0.0") == nil)
        #expect(RemoteTransport.bindableHost("::") == nil)
        #expect(RemoteTransport.bindableHost("[::]") == nil)
        #expect(RemoteTransport.bindableHost("localhost") == nil)
        #expect(RemoteTransport.bindableHost("127.0.0.1") == "127.0.0.1")
        #expect(RemoteTransport.bindableHost("[::1]") == "::1")
    }

    @Test func defaultsFollowUpstream() {
        let standard = RemoteTransport.Configuration.standard

        #expect(standard.httpPorts == 9340...9360)
        #expect(standard.webSocketPorts == 9341...9361)
        #expect(standard.socketTimeout == .seconds(20))
        #expect(standard.webSocketAuthTimeout == .seconds(10))
        #expect(standard.maxConnections == 24)
        #expect(standard.idleThreshold == 4 * 60 * 60)
    }
}

@Suite(.serialized)
struct RemoteTransportLoopbackTests {
    @Test func aRequestIsRoutedAndAnsweredWithUpstreamHeaders() async throws {
        let fixture = try await Fixture.started()
        defer { fixture.finish() }

        let response = try await fixture.http("GET /hello?x=1 HTTP/1.1\r\nHost: test\r\n\r\n")

        #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(response.contains("Cache-Control: no-store\r\n"))
        #expect(response.contains("Connection: close\r\n"))
        #expect(response.contains("X-Content-Type-Options: nosniff\r\n"))
        #expect(response.contains(#""path":"/hello""#))
        let info = await fixture.hub.info()
        let httpPort = await fixture.hub.httpPort
        let wsPort = await fixture.hub.wsPort
        #expect(RemoteLimits.httpPorts.contains(httpPort))
        #expect(RemoteLimits.webSocketPorts.contains(wsPort))
        #expect(httpPort != wsPort)
        #expect(info.httpURL == "http://127.0.0.1:\(httpPort)")
    }

    @Test func aBodyOverTheLimitIsAnsweredWith400WithoutRouting() async throws {
        let fixture = try await Fixture.started()
        defer { fixture.finish() }

        let response = try await fixture.http("POST /api/message HTTP/1.1\r\nContent-Length: \(RemoteLimits.maxBody + 1)\r\n\r\n")

        #expect(response.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
        #expect(fixture.router.calls == 0)
    }

    @Test func headersOverTheLimitAreAnsweredWith400() async throws {
        let fixture = try await Fixture.started()
        defer { fixture.finish() }

        let huge = String(repeating: "a", count: RemoteLimits.maxRequestHead + 1024)
        let response = try await fixture.http("GET / HTTP/1.1\r\nX-Pad: \(huge)\r\n\r\n")

        #expect(response.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
        #expect(fixture.router.calls == 0)
    }

    @Test func aResponseOverItsLimitIsReplacedWith400() async throws {
        let fixture = try await Fixture.started()
        defer { fixture.finish() }

        let response = try await fixture.http("GET /oversized HTTP/1.1\r\n\r\n")

        #expect(response.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
        #expect(response.contains(#"{"error":"Bad request"}"#))
    }

    @Test func aLockedOutAddressGets429BeforeParsing() async throws {
        let fixture = try await Fixture.started()
        defer { fixture.finish() }
        for _ in 0..<RemoteLimits.authFailureLimit {
            await fixture.hub.recordAuthFailure("127.0.0.1:1")
        }

        let response = try await fixture.http("GET /hello HTTP/1.1\r\n\r\n")

        #expect(response.hasPrefix("HTTP/1.1 429 Too Many Requests\r\n"))
        #expect(response.contains("Too many failed attempts"))
        #expect(fixture.router.calls == 0)
    }

    @Test func connectionsPastTheCapAreDropped() async throws {
        var configuration = RemoteTransport.Configuration.standard
        configuration.maxConnections = 1
        let fixture = try await Fixture.started(configuration: configuration)
        defer { fixture.finish() }
        let holder = TestTCPClient(port: await fixture.hub.httpPort)
        #expect(await holder.connect())
        await holder.send(Data("GET /slow HTTP/1.1\r\n".utf8))
        #expect(await eventually { await fixture.hub.connections == 1 })

        let response = try await fixture.http("GET /hello HTTP/1.1\r\n\r\n")

        #expect(response.isEmpty)
        #expect(fixture.router.calls == 0)
        holder.cancel()
    }

    @Test func aWebSocketFromAnotherOriginIsRefused() async throws {
        let fixture = try await Fixture.started()
        defer { fixture.finish() }
        let port = await fixture.hub.wsPort

        let foreign = TestWebSocketClient(port: port, origin: "http://evil.example")
        #expect(await !foreign.connect())

        let own = TestWebSocketClient(port: port, origin: await fixture.hub.allowedOrigin)
        #expect(await own.connect())
        own.cancel()
    }

    @Test func anUnauthenticatedWebSocketIsClosedAtTheAuthTimeout() async throws {
        var configuration = RemoteTransport.Configuration.standard
        configuration.webSocketAuthTimeout = .milliseconds(300)
        let fixture = try await Fixture.started(configuration: configuration)
        defer { fixture.finish() }
        let client = TestWebSocketClient(port: await fixture.hub.wsPort, origin: nil)
        #expect(await client.connect())
        let opened = ContinuousClock.now

        await client.send("hello")

        #expect(await client.receive(timeout: .seconds(5)) == .closed)
        #expect(ContinuousClock.now - opened >= .milliseconds(250))
    }

    @Test func aWrongSessionTokenIsUnauthorizedAndCountsAsAFailure() async throws {
        let fixture = try await Fixture.started()
        defer { fixture.finish() }
        let client = TestWebSocketClient(port: await fixture.hub.wsPort, origin: nil)
        #expect(await client.connect())

        await client.send(#"{"sessionToken":"not-a-session"}"#)

        let frame = await client.receive()
        #expect(frame.object?["reason"] as? String == "unauthorized")
        #expect(await client.receive() == .closed)
        for _ in 1..<RemoteLimits.authFailureLimit {
            await fixture.hub.recordAuthFailure("127.0.0.1:1")
        }
        #expect(await fixture.hub.authBlocked("127.0.0.1:1"))
    }

    @Test func theFirstFrameAuthenticatesAndRenamesTheDevice() async throws {
        let fixture = try await Fixture.started()
        defer { fixture.finish() }
        let pairing = try await fixture.pairDirectly()
        let client = TestWebSocketClient(port: await fixture.hub.wsPort, origin: nil)
        #expect(await client.connect())

        await client.send(#"{"sessionToken":"\#(pairing.sessionToken)","deviceName":"Pixel 9"}"#)

        #expect(await client.receive().object?["type"] as? String == "authenticated")
        #expect(await fixture.hub.deviceName(pairing.deviceID) == "Pixel 9")
        #expect(await fixture.hub.info().onlineDevices == 1)
        client.cancel()
    }

    @Test func aFrameOverFourKilobytesClosesTheSocket() async throws {
        let fixture = try await Fixture.started()
        defer { fixture.finish() }
        let pairing = try await fixture.pairDirectly()
        let client = TestWebSocketClient(port: await fixture.hub.wsPort, origin: nil)
        #expect(await client.connect())
        await client.send(#"{"sessionToken":"\#(pairing.sessionToken)"}"#)
        #expect(await client.receive().object?["type"] as? String == "authenticated")

        await client.send(String(repeating: "x", count: RemoteLimits.maxMessage + 1))

        #expect(await client.receive() == .closed)
    }

    @Test func subscribingToAnUnsharedTabSendsNothing() async throws {
        let fixture = try await Fixture.started()
        defer { fixture.finish() }
        let pairing = try await fixture.pairDirectly()
        let client = TestWebSocketClient(port: await fixture.hub.wsPort, origin: nil)
        #expect(await client.connect())
        await client.send(#"{"sessionToken":"\#(pairing.sessionToken)"}"#)
        #expect(await client.receive().object?["type"] as? String == "authenticated")

        await client.send(#"{"sessionToken":"\#(pairing.sessionToken)","type":"subscribe","ptyId":"pty-private"}"#)

        #expect(await client.receive(timeout: .milliseconds(500)) == .timedOut)
        #expect(await fixture.hub.subscription(pairing.deviceID) == nil)
    }

    @Test func anExpiredSessionGetsTheExpiredFrameAndIsClosed() async throws {
        let clock = TestClock()
        var configuration = RemoteTransport.Configuration.standard
        configuration.sessionCheckInterval = .milliseconds(100)
        let fixture = try await Fixture.started(configuration: configuration, clock: clock)
        defer { fixture.finish() }
        let pairing = try await fixture.pairDirectly()
        let client = TestWebSocketClient(port: await fixture.hub.wsPort, origin: nil)
        #expect(await client.connect())
        await client.send(#"{"sessionToken":"\#(pairing.sessionToken)"}"#)
        #expect(await client.receive().object?["type"] as? String == "authenticated")

        clock.advance(RemoteLimits.defaultSessionExpiry + 1)

        let frame = await client.receive()
        #expect(frame.object?["type"] as? String == "error")
        #expect(frame.object?["reason"] as? String == "expired")
        #expect(await client.receive() == .closed)
    }

    @Test func stopClosesOpenConnectionsAndRevokesDevices() async throws {
        let fixture = try await Fixture.started()
        let pairing = try await fixture.pairDirectly()
        let socket = TestWebSocketClient(port: await fixture.hub.wsPort, origin: nil)
        #expect(await socket.connect())
        await socket.send(#"{"sessionToken":"\#(pairing.sessionToken)"}"#)
        #expect(await socket.receive().object?["type"] as? String == "authenticated")
        let http = TestTCPClient(port: await fixture.hub.httpPort)
        #expect(await http.connect())
        await http.send(Data("GET /hello HTTP/1.1\r\n".utf8))
        #expect(await eventually { await fixture.hub.connections == 2 })

        await fixture.transport.stop()

        let leftover = await http.readToEnd(timeout: .seconds(5))
        #expect(leftover.map { !String(decoding: $0, as: UTF8.self).hasPrefix("HTTP/1.1 200") } == true)
        #expect(await socket.receiveUntilClosed(timeout: .seconds(5)))
        #expect(!fixture.transport.isRunning)
        #expect(await !fixture.hub.isEnabled)
        #expect(await fixture.hub.httpPort == 0)
        #expect(await fixture.hub.sessionID(for: pairing.sessionToken) == nil)
        #expect(await fixture.hub.pairingRemaining == 0)
        #expect(await eventually { await fixture.hub.connections == 0 })
        #expect(fixture.router.calls == 0)
    }

    @Test func tailscaleWithoutAnAddressFailsToStart() async throws {
        let hub = RemoteHub(resolver: RemoteHostResolver(lanAddress: { "127.0.0.1" }, tailscaleAddress: { nil }))
        await hub.setReachMode(.tailscale)
        let fixture = Fixture(hub: hub, configuration: .standard)
        defer { fixture.finish() }

        let started = await fixture.transport.start()

        #expect(!started)
        #expect(await nextEvent(hub) == .startFailed)
        #expect(await !hub.isEnabled)
        #expect(!fixture.transport.isRunning)
    }

    @Test func aBusyPortRangeEmitsStartFailed() async throws {
        let blocker = try #require(await TestListener.bound())
        defer { blocker.cancel() }
        var configuration = RemoteTransport.Configuration.standard
        configuration.httpPorts = blocker.port...blocker.port
        let fixture = Fixture(hub: RemoteHub(resolver: loopback), configuration: configuration)
        defer { fixture.finish() }

        let started = await fixture.transport.start()

        #expect(!started)
        #expect(await nextEvent(fixture.hub) == .startFailed)
        #expect(await !fixture.hub.isEnabled)
    }

    @Test func theIdleCheckTurnsEverythingOff() async throws {
        var configuration = RemoteTransport.Configuration.standard
        configuration.idleThreshold = 0.2
        configuration.idleCheckInterval = .milliseconds(50)
        let fixture = try await Fixture.started(configuration: configuration)
        defer { fixture.finish() }

        #expect(await nextEvent(fixture.hub, timeout: .seconds(5)) == .autoDisabled)
        #expect(await eventually { !fixture.transport.isRunning })
        #expect(await !fixture.hub.isEnabled)
    }

    @Test func loopbackRoundTripStreamsOneMegabyteOfOutput() async throws {
        let fixture = try await Fixture.started()
        defer { fixture.finish() }
        await fixture.hub.openPairingWindow()
        let pairingToken = await fixture.hub.pairingToken
        let body = #"{"token":"\#(pairingToken)","deviceName":"Phone"}"#
        let response = try await fixture.http(
            "POST /api/pair HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        )
        #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        let json = try #require(response.components(separatedBy: "\r\n\r\n").last)
        let sessionToken = try #require(TestFrame.text(json).object?["sessionToken"] as? String)

        let client = TestWebSocketClient(port: await fixture.hub.wsPort, origin: await fixture.hub.allowedOrigin)
        #expect(await client.connect())
        await client.send(#"{"sessionToken":"\#(sessionToken)","deviceName":"Phone"}"#)
        #expect(await client.receive().object?["type"] as? String == "authenticated")
        await client.send(#"{"sessionToken":"\#(sessionToken)","type":"subscribe","ptyId":"pty-1"}"#)
        let scrollback = try #require(await client.receive().object)
        #expect(scrollback["type"] as? String == "scrollback")
        #expect(scrollback["text"] as? String == StubTerminals.scrollback)
        #expect(scrollback["cols"] as? Int == 120)
        #expect(scrollback["rows"] as? Int == 40)

        let chunk = String(repeating: "x", count: 4096)
        let total = 1024 * 1024
        for _ in 0..<(total / chunk.count) {
            fixture.terminals.emit(.data(terminalID: "pty-1", text: chunk))
        }
        var received = 0
        while received < total {
            guard let frame = await client.receive(timeout: .seconds(10)).object else { break }
            #expect(frame["type"] as? String == "pty_output")
            #expect(frame["ptyId"] as? String == "pty-1")
            received += (frame["text"] as? String)?.utf8.count ?? 0
        }

        #expect(received == total)
        client.cancel()
    }
}
