import Darwin
import Foundation

public struct AiMemoryStatus: Equatable, Sendable {
    public var executable: String?
    public var installed: Bool
    public var running: Bool
    public var version: String?

    public init(executable: String?, installed: Bool, running: Bool, version: String?) {
        self.executable = executable
        self.installed = installed
        self.running = running
        self.version = version
    }
}

public struct AiMemoryServer: Equatable, Sendable {
    public var name: String
    public var command: String
    public var arguments: [String]
}

public enum AiMemory {
    public static let defaultCommand = "ai-memory"
    public static let serverName = "ai-memory"
    public static let endpointHost = "127.0.0.1"
    public static let endpointPort: UInt16 = 49374
    public static var endpoint: String { "\(endpointHost):\(endpointPort)" }
    public static let documentation = URL(string: "https://github.com/akitaonrails/ai-memory")!

    public static func parseVersion(output: String, exitCode: Int32) -> String? {
        guard exitCode == 0 else { return nil }
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    public static func isInstalled(exitCode: Int32?) -> Bool { exitCode == 0 }

    public static func server(enabled: Bool, executable: String?, status: AiMemoryStatus?) -> AiMemoryServer? {
        guard enabled, let executable, !executable.isEmpty else { return nil }
        if let status, status.executable == executable, !status.installed { return nil }
        return AiMemoryServer(name: serverName, command: executable, arguments: ["mcp"])
    }

    public static func detect(executable: String?, timeout: Duration = .seconds(5),
                              endpointTimeout: Duration = .milliseconds(250)) async -> AiMemoryStatus {
        async let running = LoopbackProbe.isListening(host: endpointHost, port: endpointPort, timeout: endpointTimeout)
        guard let executable else {
            return AiMemoryStatus(executable: nil, installed: false, running: await running, version: nil)
        }
        let result = await ShortCommand.run(executable, ["--version"], timeout: timeout)
        let exitCode = result?.exitCode
        return AiMemoryStatus(
            executable: executable,
            installed: isInstalled(exitCode: exitCode),
            running: await running,
            version: result.flatMap { parseVersion(output: $0.output, exitCode: $0.exitCode) }
        )
    }
}

enum ShortCommand {
    static func run(_ executable: String, _ arguments: [String], timeout: Duration) async -> (output: String, exitCode: Int32)? {
        do {
            let result = try await ExternalCommand.run(URL(filePath: executable), arguments, timeout: timeout,
                                                       discardingStderr: true)
            return (result.stdout, result.status)
        } catch .launchFailed {
            return nil
        } catch {
            return ("", SIGKILL)
        }
    }
}

enum LoopbackProbe {
    static func isListening(host: String, port: UInt16, timeout: Duration) async -> Bool {
        await Task.detached { connects(host: host, port: port, timeout: timeout) }.value
    }

    private static func connects(host: String, port: UInt16, timeout: Duration) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var noSigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return false }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let (seconds, attoseconds) = timeout.components
        let milliseconds = Int32(clamping: seconds * 1000 + attoseconds / 1_000_000_000_000_000)
        guard poll(&descriptor, 1, max(milliseconds, 1)) == 1 else { return false }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else { return false }
        return error == 0
    }
}
