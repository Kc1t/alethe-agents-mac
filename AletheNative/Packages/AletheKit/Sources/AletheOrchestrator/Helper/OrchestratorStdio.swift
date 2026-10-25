import Foundation
import AletheIntegrations

public enum OrchestratorStdio {
    public static func serve(
        input: FileHandle,
        output: FileHandle,
        handle: @escaping @Sendable (String) async -> String?
    ) async {
        let writer = LineOutput(output)
        await withTaskGroup(of: Void.self) { group in
            var buffer = Data()
            func dispatch(_ data: Data) {
                var bytes = data
                if bytes.last == UInt8(ascii: "\r") { bytes.removeLast() }
                let line = String(decoding: bytes, as: UTF8.self)
                guard !line.allSatisfy(\.isWhitespace) else { return }
                group.addTask {
                    if let reply = await handle(line) { await writer.write(reply) }
                }
            }
            do {
                for try await byte in input.bytes {
                    if byte == UInt8(ascii: "\n") {
                        dispatch(buffer)
                        buffer.removeAll(keepingCapacity: true)
                    } else {
                        buffer.append(byte)
                    }
                }
            } catch {}
            if !buffer.isEmpty { dispatch(buffer) }
            await group.waitForAll()
        }
    }

    public static func standalone(_ core: OrchestratorCore) -> @Sendable (String) async -> String? {
        { line in await OrchestratorMCP.handle(body: line, planner: nil, handler: core) }
    }
}

private actor LineOutput {
    private let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func write(_ line: String) {
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }
}

public enum OrchestratorStandalone {
    public static let codexVariable = "ALETHE_CODEX"
    public static let maxWorkersVariable = "ALETHE_MAX_WORKERS"

    public struct Setup: Sendable {
        public var configuration: OrchestratorCore.Configuration
        public var codex: URL?
    }

    public static func setup(environment: [String: String] = ProcessInfo.processInfo.environment) -> Setup {
        var launchers = WorkerLaunchers()
        let codex = resolveCodex(environment: environment)
        if let codex { launchers.set(.codexAppServer(program: codex)) }
        var configuration = OrchestratorCore.Configuration(launchers: launchers)
        if let limit = concurrencyLimit(environment: environment) { configuration.concurrencyLimit = limit }
        return Setup(configuration: configuration, codex: codex)
    }

    static func resolveCodex(environment: [String: String]) -> URL? {
        let manager = FileManager.default
        if let explicit = environment[codexVariable], !explicit.isEmpty, manager.fileExists(atPath: explicit) {
            return URL(filePath: explicit)
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") where !directory.isEmpty {
            let candidate = URL(filePath: String(directory)).appending(path: "codex")
            if manager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func concurrencyLimit(environment: [String: String]) -> Int? {
        guard let value = environment[maxWorkersVariable]?.trimmingCharacters(in: .whitespaces),
              let limit = UInt(value)
        else { return nil }
        return Int(clamping: limit)
    }
}
