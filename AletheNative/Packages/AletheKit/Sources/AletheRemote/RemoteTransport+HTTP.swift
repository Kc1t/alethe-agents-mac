import Foundation
import Network

extension RemoteTransport {
    func serveHTTP(_ socket: RemoteSocket, _ run: Run) async {
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
        let outcome = await readRequest(socket)
        if case .complete(let head, let body) = outcome {
            guard let parsed = RemoteHTTPReader.request(head: head, body: body, peerAddress: address) else {
                return await respond(socket, .error(400, "Bad request"))
            }
            request = parsed
        } else if case .failed(let error) = outcome {
            RemoteLog.logger.info("remote HTTP request refused: \(String(describing: error), privacy: .public)")
            return await respond(socket, .error(400, "Bad request"))
        } else {
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
}
