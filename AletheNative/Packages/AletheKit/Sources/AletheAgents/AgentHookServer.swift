import Foundation
import Network

public final class AgentHookServer: @unchecked Sendable {
    public typealias Handler = @Sendable (_ agent: String, _ tab: String, _ body: Data) -> Void

    public enum McpReply: Equatable, Sendable {
        case body(String)
        case accepted
        case unavailable
    }

    public typealias McpHandler = @Sendable (_ body: Data, _ planner: String?) async -> McpReply

    public static let bodyLimit = 1 << 20

    public let token: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "alethe.hooks")
    private var listener: NWListener?
    private let lock = NSLock()
    private var boundPort: UInt16?
    private var mcpHandler: McpHandler?

    public init(token: String = UUID().uuidString + UUID().uuidString, handler: @escaping Handler) {
        self.token = token.replacingOccurrences(of: "-", with: "")
        self.handler = handler
    }

    public var endpoint: String? { lock.withLock { boundPort.map { "http://127.0.0.1:\($0)" } } }

    public func start() async -> String? {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else { return nil }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        return await withCheckedContinuation { continuation in
            let resumed = LockedFlag()
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    let port = listener.port?.rawValue
                    self?.lock.withLock { self?.boundPort = port }
                    if resumed.set() { continuation.resume(returning: self?.endpoint) }
                } else if case .failed = state {
                    if resumed.set() { continuation.resume(returning: nil) }
                } else if case .cancelled = state {
                    if resumed.set() { continuation.resume(returning: nil) }
                }
            }
            listener.start(queue: queue)
        }
    }

    public func setMcpHandler(_ handler: McpHandler?) {
        lock.withLock { mcpHandler = handler }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            let parsedRequest = HTTPRequest.parse(buffer, bodyLimit: Self.bodyLimit)
            if case .incomplete = parsedRequest, !complete && error == nil {
                self.receive(connection, buffer: buffer)
            } else if case .request(let request) = parsedRequest {
                let route = self.route(request)
                if case .status(let status) = route {
                    self.respond(connection, status: status)
                } else if case .mcp(let handler, let body, let planner) = route {
                    Task {
                        let reply = await handler(body, planner)
                        if case .body(let reply) = reply {
                            self.respond(connection, status: 200, json: reply)
                        } else if case .accepted = reply {
                            self.respond(connection, status: 202)
                        } else {
                            self.respond(connection, status: 404)
                        }
                    }
                } else {
                    preconditionFailure("Unhandled value")
                }
            } else if case .tooLarge = parsedRequest {
                self.respond(connection, status: 413)
            } else {
                self.respond(connection, status: 400)
            }
        }
    }

    enum Route {
        case status(Int)
        case mcp(McpHandler, body: Data, planner: String?)
    }

    func route(_ request: HTTPRequest) -> Route {
        guard request.headers["x-alethe-token"] == token else { return .status(401) }
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        if path == "/mcp" {
            guard request.method == "POST", let handler = lock.withLock({ mcpHandler }) else { return .status(404) }
            let planner = request.headers["x-alethe-planner"].flatMap { $0.isEmpty ? nil : $0 }
            return .mcp(handler, body: request.body, planner: planner)
        }
        guard request.method == "POST", request.path.hasPrefix("/hook/"),
              let tab = request.headers["x-alethe-tab"], !tab.isEmpty else { return .status(404) }
        handler(String(request.path.dropFirst("/hook/".count)), tab, request.body)
        return .status(200)
    }

    private func respond(_ connection: NWConnection, status: Int, json: String? = nil) {
        let reasons = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
                       413: "Payload Too Large"]
        let body = Data((json ?? "").utf8)
        var head = "HTTP/1.1 \(status) \(reasons[status] ?? "OK")\r\n"
        if json != nil { head += "Content-Type: application/json\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public enum Parse: Equatable {
        case incomplete, invalid, tooLarge
        case request(HTTPRequest)
    }

    public static func parse(_ data: Data, bodyLimit: Int) -> Parse {
        let separator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: separator) else { return data.count > 64 * 1024 ? .invalid : .incomplete }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid }
        guard length <= bodyLimit else { return .tooLarge }
        let bodyStart = end.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }
        return .request(HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers,
                                    body: Data(data[bodyStart..<(bodyStart + length)])))
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() -> Bool { lock.withLock { defer { value = true }; return !value } }
}
