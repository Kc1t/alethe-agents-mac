import Foundation

public struct HealthProbeResult: Codable, Hashable, Sendable {
    public var started: Bool
    public var responded: Bool
    public var statusCode: Int?
    public var elapsedMs: Int
    public var outputTail: String
    public var terminalVerified: Bool?

    public init(started: Bool, responded: Bool, statusCode: Int?, elapsedMs: Int, outputTail: String, terminalVerified: Bool? = nil) {
        self.started = started
        self.responded = responded
        self.statusCode = statusCode
        self.elapsedMs = elapsedMs
        self.outputTail = outputTail
        self.terminalVerified = terminalVerified
    }

    public var healthy: Bool { responded && (statusCode.map { (200..<400).contains($0) } ?? false) }
}

public enum HealthProbeError: Error, Equatable, Sendable {
    case environmentNotFound
    case spawnFailed(String)
}

public struct HealthProbe: Sendable {
    public static let maxOutputTail = 8 * 1024

    public var shell: URL
    public init(shell: URL = URL(fileURLWithPath: "/bin/sh")) { self.shell = shell }

    public static func probeURL(port: Int, path: String?) -> URL? {
        let trimmed = (path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "/" : (trimmed.hasPrefix("/") ? trimmed : "/" + trimmed)
        return URL(string: "http://127.0.0.1:\(port)\(normalized)")
    }

    public static func capped(_ text: String, limit: Int) -> String {
        let utf8 = text.utf8
        guard utf8.count > limit else { return text }
        var index = utf8.index(utf8.endIndex, offsetBy: -limit)
        while index < utf8.endIndex, String.Index(index, within: text) == nil { index = utf8.index(after: index) }
        return String(text[index...])
    }

    public static func isAletheCore(healthBody data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["service"] as? String == "alethe-core"
    }

    public static func effectiveTimeout(ms: Int) -> Int { max(ms, 1000) }

    public func run(in directory: URL, startCommand: String, path: String?, timeoutMs: Int = 8000) async throws -> HealthProbeResult {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            throw HealthProbeError.environmentNotFound
        }
        let start = Date()
        let port = try Self.freePort()
        let buffer = OutputBuffer()

        var env = ProcessInfo.processInfo.environment
        env["PORT"] = String(port)
        let process = try GroupProcess.spawn(shell: shell, command: startCommand, directory: directory, environment: env)
        process.output.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { buffer.append(data) }
        }
        defer {
            process.killTree()
            process.output.readabilityHandler = nil
        }

        var responded = false
        var status: Int?
        if let url = Self.probeURL(port: port, path: path) {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 3
            let session = URLSession(configuration: config)
            let deadline = start.addingTimeInterval(Double(Self.effectiveTimeout(ms: timeoutMs)) / 1000)
            while Date() < deadline, !Task.isCancelled {
                if let (_, response) = try? await session.data(from: url), let http = response as? HTTPURLResponse {
                    responded = true
                    status = http.statusCode
                    break
                }
                if !process.isRunning { break }
                try? await Task.sleep(for: .milliseconds(400))
            }
            session.invalidateAndCancel()
        }
        return HealthProbeResult(
            started: true, responded: responded, statusCode: status,
            elapsedMs: Int(Date().timeIntervalSince(start) * 1000),
            outputTail: Self.capped(buffer.text, limit: Self.maxOutputTail))
    }

    static func freePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HealthProbeError.spawnFailed("socket") }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr -> Bool in
                bind(fd, ptr, len) == 0 && getsockname(fd, ptr, &len) == 0
            }
        }
        guard bound else { throw HealthProbeError.spawnFailed("bind") }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        if data.count > HealthProbe.maxOutputTail * 2 { data.removeFirst(data.count - HealthProbe.maxOutputTail) }
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
