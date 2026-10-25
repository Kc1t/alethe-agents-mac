import AletheFoundation
import AletheGit
import AletheMerge
import AletheOrchestrator
import Foundation
import Observation

enum ApplyWorktreePhase: Equatable {
    case idle
    case previewing
    case confirming(WorktreeApplyPreview)
    case running(WorktreeApplyStep)
    case applied(target: String)
    case nothingToApply
    case handedOff(environmentID: String)
    case failed(String)

    var isBusy: Bool {
        if case .previewing = self {
            return true
        } else if case .running = self {
            return true
        } else {
            return false
        }
    }
}

@Observable
@MainActor
final class ApplyWorktreeCenter {
    static let shared = ApplyWorktreeCenter()

    private(set) var phases: [String: ApplyWorktreePhase] = [:]
    @ObservationIgnored var operations: WorktreeApplyOperations = .live()
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generations: [String: Int] = [:]

    func phase(_ job: String) -> ApplyWorktreePhase { phases[job] ?? .idle }

    func review(_ job: JobSnapshot) {
        guard let path = job.worktree, !phase(job.id).isBusy else { return }
        if case .applied = phase(job.id) { return }
        let apply = WorktreeApply(operations: operations)
        let (id, worktree) = (job.id, URL(filePath: path, directoryHint: .isDirectory))
        start(id, .previewing) { generation in
            let result = await Task.detached { () -> Result<WorktreeApplyPreview, Error> in
                do { return .success(try await apply.preview(worktree: worktree, agentID: id)) } catch { return .failure(error) }
            }.value
            guard self.isCurrent(id, generation) else { return }
            if case .success(let preview) = result {
                self.phases[id] = .confirming(preview)
            } else if case .failure(let error) = result {
                self.fail(id, error)
            }
        }
    }

    func confirm(_ job: String, projectID: String?, bus: EventBus?, openMergeCenter: @escaping @MainActor @Sendable (String) -> Void) {
        guard case .confirming(let preview) = phase(job) else { return }
        let apply = WorktreeApply(operations: operations)
        start(job, .running(.committing)) { generation in
            let events = EventOutbox(bus: bus)
            let work = Task.detached { () -> Result<WorktreeApplyResult, Error> in
                do {
                    return .success(try await apply.run(preview, projectID: projectID) { step in
                        Task { @MainActor in self.advance(job, generation, to: step) }
                    })
                } catch { return .failure(error) }
            }
            let outcome = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard self.isCurrent(job, generation) else { return }
            self.tasks[job] = nil
            if case .success(let result) = outcome {
                Self.publish(result, preview: preview, projectID: projectID, to: events)
                self.finish(job, result, preview: preview, openMergeCenter: openMergeCenter)
            } else if case .failure(let error) = outcome {
                self.fail(job, error)
            }
        }
    }

    func cancel(_ job: String) {
        let matchedValue = phase(job)
        if case .previewing = matchedValue {
            stop(job)
            phases[job] = nil
        } else if case .confirming = matchedValue {
            stop(job)
            phases[job] = nil
        } else if case .running(let step) = matchedValue, step.isCancelable {
            tasks[job]?.cancel()
        } else {
        }
    }

    func dismiss(_ job: String) {
        let matchedValue = phase(job)
        if case .failed = matchedValue {
            phases[job] = nil
        } else if case .nothingToApply = matchedValue {
            phases[job] = nil
        } else if case .handedOff = matchedValue {
            phases[job] = nil
        } else {
        }
    }

    private func start(_ job: String, _ phase: ApplyWorktreePhase, _ body: @escaping @MainActor @Sendable (Int) async -> Void) {
        stop(job)
        let generation = (generations[job] ?? 0) + 1
        generations[job] = generation
        phases[job] = phase
        tasks[job] = Task { await body(generation) }
    }

    private func stop(_ job: String) {
        tasks[job]?.cancel()
        tasks[job] = nil
        generations[job, default: 0] += 1
    }

    private func isCurrent(_ job: String, _ generation: Int) -> Bool { generations[job] == generation }

    private func advance(_ job: String, _ generation: Int, to step: WorktreeApplyStep) {
        guard isCurrent(job, generation), case .running = phase(job) else { return }
        phases[job] = .running(step)
    }

    private func finish(_ job: String, _ result: WorktreeApplyResult, preview: WorktreeApplyPreview,
                        openMergeCenter: @MainActor (String) -> Void) {
        if case .applied = result.outcome {
            phases[job] = .applied(target: preview.target)
        } else if case .nothingToApply = result.outcome {
            phases[job] = .nothingToApply
        } else if case .cancelled = result.outcome {
            phases[job] = nil
        } else if case .conflicted(let environment) = result.outcome {
            phases[job] = .handedOff(environmentID: environment)
            openMergeCenter(environment)
        } else if case .notMerged(let environment, let stage, let output) = result.outcome {
            AppLog.shown("Applying \(job) stopped at \(stage.rawValue): \(output)", .orchestrator, level: .warning)
            phases[job] = .handedOff(environmentID: environment)
            openMergeCenter(environment)
        }
    }

    private func fail(_ job: String, _ error: Error) {
        tasks[job] = nil
        let message = Self.describe(error)
        AppLog.shown("Applying \(job) failed: \(message)", .orchestrator)
        phases[job] = .failed(message)
    }

    static func describe(_ error: Error) -> String {
        if case WorktreeApplyError.detachedTarget = error {
            return String(localized: "orchestrator.apply.error.detached")
        } else if case WorktreeApplyError.sameBranch(let branch) = error {
            return String(format: String(localized: "orchestrator.apply.error.sameBranch"), branch)
        } else if case GitWorktreeError.notFound = error {
            return String(localized: "orchestrator.apply.error.gone")
        } else {
            return String(describing: error)
        }
    }

    private static func publish(_ result: WorktreeApplyResult, preview: WorktreeApplyPreview, projectID: String?,
                                to events: EventOutbox) {
        if let analysis = result.analysis {
            events.publish(.mergeAnalyzed(projectID: projectID, source: analysis.source, target: analysis.target,
                                          clean: analysis.clean, conflictCount: analysis.conflicts.count,
                                          classes: analysis.classes.map(\.variantName)))
        }
        guard let environment = result.environment else { return }
        events.publish(BusEvent.mergePrepared(
            environmentID: environment.id, projectID: projectID, source: preview.source, target: preview.target,
            clean: environment.clean, conflictCount: environment.conflicts.count, environmentPath: environment.path.path))
        if result.outcome == .applied {
            events.publish(.mergeMerged(environmentID: environment.id, projectID: projectID,
                                        source: preview.source, target: preview.target))
        }
    }
}
