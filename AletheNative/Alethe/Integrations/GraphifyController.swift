import AletheAgents
import AletheFoundation
import AletheIntegrations
import AletheModel
import Foundation
import Observation

@Observable
@MainActor
final class GraphifyController {
    static let mcpServerName = "graphify"

    @ObservationIgnored let service = GraphifyService()
    private(set) var status: GraphifyStatus?
    private(set) var isDetecting = false
    private(set) var generating: Set<URL> = []
    private(set) var revisions: [URL: Int] = [:]
    private(set) var failures: [URL: String] = [:]
    @ObservationIgnored private weak var environment: AppEnvironment?
    @ObservationIgnored private var roots: [String: URL] = [:]
    @ObservationIgnored private let events = EventOutbox()

    func start(environment: AppEnvironment) {
        self.environment = environment
        events.attach(environment.multiagent.bus)
        environment.terminals.mcp.register(Self.mcpServerName) { [weak self] context in
            self?.servers(for: context) ?? []
        }
    }

    var executable: String? {
        guard let environment else { return nil }
        let configured = environment.preferences?.document.graphifyCommand?.trimmingCharacters(in: .whitespaces) ?? ""
        if configured.isEmpty { return environment.launchers.resolve(GraphifyService.defaultCommand) }
        guard configured.contains("/") || configured.hasPrefix("~") else { return environment.launchers.resolve(configured) }
        let path = (configured as NSString).expandingTildeInPath
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    func detect() async {
        isDetecting = true
        let executable = executable
        status = await service.detect(executable: executable)
        isDetecting = false
    }

    func root(for directory: String) -> URL {
        if let cached = roots[directory] { return cached }
        let url = URL(filePath: directory, directoryHint: .isDirectory)
        guard let root = GraphifyRepository.repositoryRoot(containing: url) else { return url.standardizedFileURL }
        roots[directory] = root
        return root
    }

    func isGenerating(_ root: URL) -> Bool { generating.contains(root.standardizedFileURL) }

    func ensureGraph(root: URL) {
        let root = root.standardizedFileURL
        let executable = executable
        let wasGenerating = generating.contains(root)
        generating.insert(root)
        Task {
            let result = await service.ensureGraph(root: root, executable: executable) { outcome in
                Task { @MainActor [weak self] in self?.finished(root, outcome, action: "bootstrap") }
            }
            if result == .exists || result == .unavailable, !wasGenerating { generating.remove(root) }
        }
    }

    @discardableResult
    func generate(root: URL) async -> GraphifyGenerationOutcome {
        let root = root.standardizedFileURL
        guard let executable else {
            let outcome = GraphifyGenerationOutcome.failed(String(localized: "graphify.notFound"))
            failures[root] = String(localized: "graphify.notFound")
            return outcome
        }
        generating.insert(root)
        let outcome = await service.generate(root: root, executable: executable)
        finished(root, outcome, action: "generate")
        return outcome
    }

    func cancelGeneration(root: URL) {
        Task { await service.cancelGeneration(root: root.standardizedFileURL) }
    }

    func rollback(root: URL, to snapshot: String) async throws {
        try await service.rollback(root: root, to: snapshot)
        revisions[root.standardizedFileURL, default: 0] += 1
        events.publish(.graphRolledBack(snapshotID: snapshot))
    }

    private func finished(_ root: URL, _ outcome: GraphifyGenerationOutcome, action: String) {
        generating.remove(root)
        if case .generated = outcome {
            failures[root] = nil
            revisions[root, default: 0] += 1
            events.publish(.graphGenerated(repository: root.path, action: action))
        } else if case .failed(let message) = outcome {
            failures[root] = message.isEmpty ? String(localized: "graphify.generationFailed") : message
            AppLog.record(.warning, .integrations, "Graphify generation failed: \(message)")
        } else if case .timedOut = outcome {
            failures[root] = String(localized: "graphify.generationTimedOut")
            AppLog.record(.warning, .integrations, "Graphify generation timed out")
        } else if case .cancelled = outcome {
        }
    }

    private func servers(for context: McpLaunchContext) -> [McpLaunchServer] {
        guard let environment, environment.features.isOn(.graphify), context.project.usesGraphify,
              McpLaunchConfig.supports(context.kind), let executable else { return [] }
        let root = root(for: context.workingDirectory)
        ensureGraph(root: root)
        return [McpLaunchServer(name: Self.mcpServerName, command: executable,
                                arguments: GraphifyService.mcpArguments(root: root))]
    }
}
