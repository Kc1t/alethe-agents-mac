import AletheAgents
import AletheDesign
import AletheFoundation
import AletheGit
import AletheMerge
import AletheModel
import SwiftUI

@MainActor @Observable
final class MergeCenterModel {
    let folder: URL
    let projectID: ProjectID?
    private(set) var root: URL?
    private(set) var branches: [String] = []
    var source = ""
    var target = ""
    var stage = MergeCenterStage.analyze {
        didSet { if stage != oldValue { recordStage() } }
    }
    private(set) var environment: ConflictEnvironment?
    private(set) var conflicts: [ConflictFile] = []
    var commandsText = ""
    var healthCheckCommand: String?
    var healthCheckPath: String?
    private(set) var note: String?
    private(set) var merged = false
    private(set) var outcome: MergeFinishOutcome?
    private(set) var analysis: MergeAnalysis?
    private(set) var loading = true
    private(set) var running = false
    private(set) var error: String? { didSet { if error != oldValue { AppLog.shown(error, .git) } } }
    private var task: Task<Void, Never>?
    @ObservationIgnored let events: EventOutbox

    init(folder: URL, projectID: ProjectID? = nil, bus: EventBus? = nil) {
        self.folder = folder
        self.projectID = projectID
        events = EventOutbox(bus: bus)
    }

    var canAnalyze: Bool { root != nil && !source.isEmpty && !target.isEmpty && source != target }

    func load(resume id: String? = nil) async {
        defer { loading = false }
        do {
            let root = try await GitRepository.discover(folder)
            self.root = root
            let repository = GitRepository(root: root)
            branches = try await repository.branches().filter { !$0.isRemote }.map(\.name).sorted()
            let current = try await repository.currentBranch()
            target = current ?? branches.first ?? ""
            source = branches.first { $0 != target } ?? ""
            commandsText = ValidationSettings.suggested(for: root).commands.joined(separator: "\n")
            if let id { try await resume(id: id, root: root) }
        } catch {
            self.error = String(describing: error)
        }
    }

    private func resume(id: String, root: URL) async throws {
        let (env, meta) = try await Task.detached { try await ConflictResolution(root: root).resume(id: id) }.value
        source = meta.source
        target = meta.target
        environment = env
        conflicts = env.conflicts
        if let report = meta.lastValidation {
            outcome = MergeFinishOutcome(
                merged: false, stage: report.status == .failed ? .validation : .validated, output: "",
                validation: report, contractWarnings: meta.contractWarnings)
        }
        stage = MergeResumePoint.stage(recorded: meta.stage, conflictPaths: meta.conflictPaths,
                                       unresolved: env.conflicts.map(\.path))
    }

    private func recordStage() {
        guard let root, let id = environment?.id, stage != .analyze else { return }
        let (stage, report, warnings) = (stage, outcome?.validation, outcome?.contractWarnings)
        Task.detached {
            try? ConflictResolution(root: root).updateMeta(id: id) {
                $0.stage = stage
                if let report {
                    $0.lastValidation = report
                    $0.contractWarnings = warnings
                }
            }
        }
    }

    func analyze() {
        guard let root, canAnalyze else { return }
        let (source, target) = (source, target)
        running = true
        error = nil
        analysis = nil
        task = Task {
            let work = Task.detached {
                do { return Result<MergeAnalysis, Error>.success(
                    try await MergeAnalyzer(root: root).analyze(source: source, target: target)) }
                catch { return .failure(error) }
            }
            let outcome = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            if case .success(let result) = outcome {
                analysis = result
                events.publish(.mergeAnalyzed(projectID: projectID?.rawValue, source: result.source, target: result.target,
                                              clean: result.clean, conflictCount: result.conflicts.count,
                                              classes: result.classes.map(\.variantName)))
            }
            if case .failure(let failure) = outcome {
                error = String(describing: failure)
            }
            running = false
        }
    }

    private var handle: MergeEnvHandle? {
        environment.map { MergeEnvHandle(id: $0.id, source: source, target: target, conflictPaths: conflicts.map(\.path)) }
    }

    private var settings: ValidationSettings {
        ValidationSettings(commands: commandsText.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            healthCheckCommand: healthCheckCommand, healthCheckPath: healthCheckPath)
    }

    private func perform<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T,
                                      then apply: @escaping @MainActor (T) -> Void) {
        running = true
        error = nil
        task = Task {
            let work = Task.detached { () -> Result<T, Error> in
                do { return .success(try await operation()) } catch { return .failure(error) }
            }
            let outcome = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            if case .success(let value) = outcome {
                apply(value)
            }
            if case .failure(let failure) = outcome {
                error = String(describing: failure)
            }
            running = false
        }
    }

    func prepare() {
        guard let root else { return }
        let (source, target) = (source, target)
        let projectID = projectID?.rawValue
        perform({ try await ConflictResolution(root: root).prepare(source: source, target: target, projectId: projectID) }) { env in
            self.events.publish(BusEvent.mergePrepared(
                environmentID: env.id, projectID: projectID, source: source, target: target, clean: env.clean,
                conflictCount: env.conflicts.count, environmentPath: env.path.path))
            self.environment = env
            self.conflicts = env.conflicts
            self.note = nil
            self.stage = env.clean ? .validate : .prepare
        }
    }

    func refreshConflicts() {
        guard let root, let id = environment?.id else { return }
        perform({ try await ConflictResolution(root: root).conflicts(id: id) }) { self.conflicts = $0 }
    }

    func rebase() {
        guard let root, let id = environment?.id else { return }
        perform({ try await ConflictResolution(root: root).rebaseOntoTarget(id: id) }) { outcome in
            self.note = outcome.output
            if case .conflicted(let files) = outcome { self.conflicts = files }
        }
    }

    func abort() {
        guard let root, let id = environment?.id else { return }
        perform({ try await ConflictResolution(root: root).abort(id: id) }) { _ in
            self.events.publish(.mergeAborted(environmentID: id, projectID: self.projectID?.rawValue))
            self.reset()
        }
    }

    func validate() {
        guard let root, let handle else { return }
        let settings = settings
        perform({ try await MergeFinisher(root: root).validate(handle, settings: settings) }) { outcome in
            self.publishEvents(of: outcome, handle: handle)
            self.note = Self.describe(outcome)
            self.outcome = outcome
            self.recordStage()
        }
    }

    func finalize() {
        guard let root, let handle else { return }
        let settings = settings
        perform({ try await MergeFinisher(root: root).finalize(handle, settings: settings) }) { outcome in
            self.publishEvents(of: outcome, handle: handle)
            self.note = Self.describe(outcome)
            self.outcome = outcome
            self.merged = outcome.merged
            if outcome.merged { self.environment = nil }
        }
    }

    private func publishEvents(of outcome: MergeFinishOutcome, handle: MergeEnvHandle) {
        let projectID = projectID?.rawValue
        if let report = outcome.validation {
            let failed = outcome.stage == .validation ? (report.failedCommand ?? report.status.rawValue) : nil
            events.publish(.mergeValidation(environmentID: handle.id, projectID: projectID, failedStage: failed))
        }
        if outcome.merged {
            events.publish(.mergeMerged(environmentID: handle.id, projectID: projectID,
                                        source: handle.source, target: handle.target))
        }
    }

    func forceCleanup() {
        guard let root, let handle else { return }
        perform({ try await MergeFinisher(root: root).forceCleanup(handle) }) { _ in self.reset() }
    }

    private func reset() {
        environment = nil
        conflicts = []
        note = nil
        outcome = nil
        merged = false
        stage = .analyze
    }

    private static func describe(_ outcome: MergeFinishOutcome) -> String {
        "[\(outcome.stage.rawValue)] \(outcome.output)"
    }

    func cancel() {
        task?.cancel()
        task = nil
        running = false
    }
}
