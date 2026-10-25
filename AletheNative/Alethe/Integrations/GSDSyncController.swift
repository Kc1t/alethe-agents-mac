import AletheAgents
import AletheFoundation
import AletheIntegrations
import AletheModel
import Foundation
import Observation

@Observable
@MainActor
final class GSDSyncController {
    static let pollInterval: Duration = .seconds(5)
    static let openCodeAgent = "opencode"

    private(set) var sessions: [GSDSyncSession] = []
    @ObservationIgnored private(set) var service: GSDSyncService?
    @ObservationIgnored private weak var environment: AppEnvironment?
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var polling = false

    func start(environment: AppEnvironment, profileDirectory: URL) {
        self.environment = environment
        service = GSDSyncService(profileDirectory: profileDirectory)
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        poll?.cancel()
        poll = nil
    }

    func isAvailable(in project: Project?) -> Bool {
        guard let project, environment?.features.isOn(.gsdSync) == true else { return false }
        return Self.runsOpenCode(project)
    }

    static func runsOpenCode(_ project: Project) -> Bool {
        project.panes.contains { $0.tabs.contains { $0.agent == openCodeAgent } }
    }

    func sessions(of project: ProjectID) -> [GSDSyncSession] {
        sessions.filter { $0.projectID == project.rawValue }
    }

    static func targets(in document: WorkspaceDocument) -> [GSDSyncTarget] {
        document.projects.flatMap { project in
            project.panes.flatMap(\.tabs).filter { $0.agent == openCodeAgent }.map { tab in
                GSDSyncTarget(projectID: project.id.rawValue,
                              directory: URL(filePath: tab.workingDirectory ?? project.folder, directoryHint: .isDirectory))
            }
        }
    }

    func refresh() async {
        guard !polling, let environment, let service else { return }
        guard environment.features.isOn(.gsdSync), let document = environment.workspace?.document else {
            if !sessions.isEmpty { sessions = [] }
            return
        }
        let targets = Self.targets(in: document)
        guard !targets.isEmpty else {
            if !sessions.isEmpty { sessions = [] }
            return
        }
        polling = true
        defer { polling = false }
        let found = await service.sessions(for: targets)
        guard !Task.isCancelled else { return }
        for session in found {
            guard let error = session.error else { continue }
            reportChildError(error, in: session)
        }
        if found != sessions { sessions = found }
    }

    private func reportChildError(_ error: String, in session: GSDSyncSession) {
        AppLog.record(.warning, .integrations, "GSD Sync child session failed in \(session.name)")
        environment?.notifier.post(title: String(localized: "gsdSync.childError"), body: String(error.prefix(300)),
                                   agent: Self.openCodeAgent)
    }

    func prepareLaunch(in directory: String) async {
        guard let environment, environment.features.isOn(.gsdSync), let service else { return }
        let chain = environment.preferences?.document.gsdSyncModelChain ?? []
        do {
            _ = try await service.installPlugin(at: URL(filePath: directory, directoryHint: .isDirectory), modelChain: chain)
        } catch {
            AppLog.record(.warning, .integrations, "GSD Sync plugin was not installed: \(error)")
        }
    }

    var openCodeExecutable: String? {
        environment?.launchers.resolve(Self.openCodeAgent, override: environment?.preferences?.document.cliPaths?[Self.openCodeAgent])
    }
}
