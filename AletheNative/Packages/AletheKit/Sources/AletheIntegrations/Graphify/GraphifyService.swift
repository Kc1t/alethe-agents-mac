import Foundation

public struct GraphifyStatus: Hashable, Sendable {
    public var available: Bool
    public var executable: String?
    public var version: String?

    public init(available: Bool, executable: String?, version: String? = nil) {
        self.available = available
        self.executable = executable
        self.version = version
    }
}

public enum GraphifyEnsureResult: String, Sendable {
    case exists, generating, unavailable, started
}

public enum GraphifyGenerationOutcome: Equatable, Sendable {
    case generated
    case failed(String)
    case cancelled
    case timedOut
}

public actor GraphifyService {
    public static let defaultCommand = "graphify"
    public static let probeTimeout: Duration = .seconds(10)
    public static let generationTimeout: Duration = .seconds(15 * 60)

    private var generations: [URL: Task<GraphifyGenerationOutcome, Never>] = [:]
    private let generationTimeout: Duration

    public init(generationTimeout: Duration = GraphifyService.generationTimeout) {
        self.generationTimeout = generationTimeout
    }

    public nonisolated static func mcpArguments(root: URL) -> [String] {
        [root.standardizedFileURL.path, "--mcp"]
    }

    public nonisolated func detect(executable: String?) async -> GraphifyStatus {
        guard let executable else { return GraphifyStatus(available: false, executable: nil) }
        guard let result = try? await ExternalCommand.run(executable, ["--version"], timeout: Self.probeTimeout),
              result.succeeded else {
            return GraphifyStatus(available: false, executable: executable)
        }
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return GraphifyStatus(available: true, executable: executable, version: version.isEmpty ? nil : version)
    }

    public func isGenerating(_ root: URL) -> Bool { generations[root.standardizedFileURL] != nil }

    public func ensureGraph(root: URL, executable: String?,
                            onFinish: (@Sendable (GraphifyGenerationOutcome) -> Void)? = nil) async -> GraphifyEnsureResult {
        let root = root.standardizedFileURL
        let repository = GraphifyRepository(root: root)
        if await Task.detached(operation: { repository.hasGraph }).value { return .exists }
        if generations[root] != nil { return .generating }
        guard await detect(executable: executable).available, let executable else { return .unavailable }
        if generations[root] != nil { return .generating }
        startGeneration(root: root, executable: executable, onFinish: onFinish)
        return .started
    }

    public func generate(root: URL, executable: String) async -> GraphifyGenerationOutcome {
        let root = root.standardizedFileURL
        let task = generations[root] ?? startGeneration(root: root, executable: executable, onFinish: nil)
        return await task.value
    }

    public func cancelGeneration(root: URL) {
        generations[root.standardizedFileURL]?.cancel()
    }

    @discardableResult
    private func startGeneration(root: URL, executable: String,
                                 onFinish: (@Sendable (GraphifyGenerationOutcome) -> Void)?) -> Task<GraphifyGenerationOutcome, Never> {
        let timeout = generationTimeout
        let task = Task<GraphifyGenerationOutcome, Never> {
            let outcome: GraphifyGenerationOutcome
            do {
                let result = try await ExternalCommand.run(executable, [root.path], directory: root, timeout: timeout)
                outcome = result.succeeded ? .generated
                    : .failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch ExternalCommandError.cancelled {
                outcome = .cancelled
            } catch ExternalCommandError.timedOut {
                outcome = .timedOut
            } catch ExternalCommandError.launchFailed(let message) {
                outcome = .failed(message)
            } catch {
                outcome = Task.isCancelled ? .cancelled : .failed(error.localizedDescription)
            }
            self.finished(root)
            onFinish?(outcome)
            return outcome
        }
        generations[root] = task
        return task
    }

    private func finished(_ root: URL) { generations[root] = nil }

    public nonisolated func readGraph(root: URL, limit: Int = GraphData.visualizationLimit) async throws -> GraphData {
        try await Self.detached { try GraphifyRepository(root: root).readGraph(limit: limit) }
    }

    public nonisolated func snapshot(root: URL) async throws -> GraphSnapshot {
        try await Self.detached { try GraphifyRepository(root: root).snapshot() }
    }

    public nonisolated func snapshots(root: URL) async -> [GraphSnapshot] {
        await Task.detached { GraphifyRepository(root: root).snapshots() }.value
    }

    public nonisolated func diff(root: URL, base: String, compare: String? = nil) async throws -> GraphDiff {
        try await Self.detached { try GraphifyRepository(root: root).diff(base: base, compare: compare) }
    }

    public nonisolated func rollback(root: URL, to id: String) async throws {
        try await Self.detached { try GraphifyRepository(root: root).rollback(to: id) }
    }

    @discardableResult
    public nonisolated func prune(root: URL, keepLast: Int, maxAgeDays: Int? = nil) async -> Int {
        await Task.detached { GraphifyRepository(root: root).prune(keepLast: keepLast, maxAgeDays: maxAgeDays) }.value
    }

    private static func detached<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(operation: work).value
    }
}
