import Foundation

public struct GSDSyncService: Sendable {
    public let writer: ConfigFileWriter

    public init(writer: ConfigFileWriter) {
        self.writer = writer
    }

    public init(profileDirectory: URL) {
        self.init(writer: ConfigFileWriter(profileDirectory: profileDirectory))
    }

    public func planningStatus(at path: URL) async -> PlanningStatus? {
        await Self.offActor { PlanningGate.repositoryRoot(containing: path).map(PlanningGate.status(of:)) }
    }

    public func childState(at path: URL) async -> GSDChildState? {
        await Self.offActor { PlanningGate.repositoryRoot(containing: path).map(PlanningGate.childState(of:)) }
    }

    public func procedure(at path: URL) async -> [GSDProcedureStep] {
        await Self.offActor { PlanningGate.repositoryRoot(containing: path).map(PlanningGate.procedure(of:)) ?? [] }
    }

    public func plans(at path: URL, projectID: String) async -> [ProjectPlan] {
        await Self.offActor { ProjectPlans.list(root: PlanningGate.repositoryRoot(containing: path) ?? path, projectID: projectID) }
    }

    public func installPlugin(at path: URL, modelChain: [String]) async throws(GSDOpenCodePlugin.InstallError) -> GSDPluginInstallReport? {
        let writer = writer
        let result: Result<GSDPluginInstallReport?, GSDOpenCodePlugin.InstallError> = await Self.offActor {
            guard let root = PlanningGate.repositoryRoot(containing: path) else { return .success(nil) }
            do throws(GSDOpenCodePlugin.InstallError) {
                return .success(try GSDOpenCodePlugin.install(root: root, modelChain: modelChain, writer: writer))
            } catch {
                return .failure(error)
            }
        }
        return try result.get()
    }

    public func export(sessionID: String, at path: URL, openCode executable: URL) async throws(OpenCodeExportError) -> OpenCodeExportSession {
        let directory = await Self.offActor { PlanningGate.repositoryRoot(containing: path) } ?? path
        return try await OpenCodeExport.run(sessionID: sessionID, directory: directory, executable: executable)
    }

    private static func offActor<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await Task.detached(priority: .utility, operation: work).value
    }
}
