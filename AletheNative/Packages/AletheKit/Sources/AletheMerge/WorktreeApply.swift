import AletheGit
import Foundation

public enum WorktreeApplyStep: String, Sendable, Hashable, CaseIterable {
    case committing, fetching, analyzing, preparing, finalizing

    public var isCancelable: Bool { self != .finalizing }
}

public struct WorktreeApplyPreview: Sendable, Hashable {
    public var root: URL
    public var agentID: String
    public var source: String
    public var target: String
    public var pending: [String]
    public var committed: [String]

    public init(root: URL, agentID: String, source: String, target: String, pending: [String], committed: [String]) {
        self.root = root
        self.agentID = agentID
        self.source = source
        self.target = target
        self.pending = pending
        self.committed = committed
    }

    public var files: [String] { Array(Set(pending + committed)).sorted() }
}

public enum WorktreeApplyOutcome: Sendable, Hashable {
    case applied
    case conflicted(environmentID: String)
    case notMerged(environmentID: String, stage: MergeFinishOutcome.Stage, output: String)
    case nothingToApply
    case cancelled
}

public struct WorktreeApplyResult: Sendable, Hashable {
    public var outcome: WorktreeApplyOutcome
    public var committedPending: Bool
    public var analysis: MergeAnalysis?
    public var environment: ConflictEnvironment?

    public init(outcome: WorktreeApplyOutcome, committedPending: Bool = false,
                analysis: MergeAnalysis? = nil, environment: ConflictEnvironment? = nil) {
        self.outcome = outcome
        self.committedPending = committedPending
        self.analysis = analysis
        self.environment = environment
    }
}

public enum WorktreeApplyError: Error, Equatable, Sendable {
    case detachedTarget
    case sameBranch(String)
}

public struct WorktreeApplyOperations: Sendable {
    public var mainRoot: @Sendable (_ worktree: URL) async throws -> URL
    public var currentBranch: @Sendable (_ root: URL) async throws -> String?
    public var pendingChanges: @Sendable (_ root: URL, _ agentID: String) async throws -> [String]
    public var committedFiles: @Sendable (_ root: URL, _ source: String, _ target: String) async -> [String]
    public var commitPending: @Sendable (_ root: URL, _ agentID: String, _ message: String) async throws -> Bool
    public var fetchBranch: @Sendable (_ root: URL, _ agentID: String) async throws -> Void
    public var analyze: @Sendable (_ root: URL, _ source: String, _ target: String) async throws -> MergeAnalysis
    public var prepare: @Sendable (_ root: URL, _ source: String, _ target: String, _ projectID: String?) async throws -> ConflictEnvironment
    public var finalize: @Sendable (_ root: URL, _ handle: MergeEnvHandle) async throws -> MergeFinishOutcome
    public var abort: @Sendable (_ root: URL, _ handle: MergeEnvHandle) async throws -> Void

    public init(
        mainRoot: @escaping @Sendable (URL) async throws -> URL,
        currentBranch: @escaping @Sendable (URL) async throws -> String?,
        pendingChanges: @escaping @Sendable (URL, String) async throws -> [String],
        committedFiles: @escaping @Sendable (URL, String, String) async -> [String],
        commitPending: @escaping @Sendable (URL, String, String) async throws -> Bool,
        fetchBranch: @escaping @Sendable (URL, String) async throws -> Void,
        analyze: @escaping @Sendable (URL, String, String) async throws -> MergeAnalysis,
        prepare: @escaping @Sendable (URL, String, String, String?) async throws -> ConflictEnvironment,
        finalize: @escaping @Sendable (URL, MergeEnvHandle) async throws -> MergeFinishOutcome,
        abort: @escaping @Sendable (URL, MergeEnvHandle) async throws -> Void
    ) {
        self.mainRoot = mainRoot
        self.currentBranch = currentBranch
        self.pendingChanges = pendingChanges
        self.committedFiles = committedFiles
        self.commitPending = commitPending
        self.fetchBranch = fetchBranch
        self.analyze = analyze
        self.prepare = prepare
        self.finalize = finalize
        self.abort = abort
    }

    public static func live(runner: GitRunner = GitRunner()) -> WorktreeApplyOperations {
        let worktrees = GitWorktrees(runner: runner)
        return WorktreeApplyOperations(
            mainRoot: { try await worktrees.mainRepositoryRoot($0) },
            currentBranch: { try await GitRepository(root: $0, runner: runner).currentBranch() },
            pendingChanges: { try await worktrees.pendingChanges(repo: $0, agentId: $1).map(\.path) },
            committedFiles: { root, source, target in
                let output = try? await runner.run(["diff", "--name-only", "-z", "\(target)...\(source)", "--"],
                                                   in: root, allowedExitCodes: [0])
                return output?.text.split(separator: "\0").map(String.init).filter { !$0.isEmpty } ?? []
            },
            commitPending: { try await worktrees.commitPending(repo: $0, agentId: $1, message: $2) },
            fetchBranch: { try await worktrees.fetchBranch(repo: $0, agentId: $1) },
            analyze: { try await MergeAnalyzer(root: $0, runner: runner).analyze(source: $1, target: $2) },
            prepare: { try await ConflictResolution(root: $0, runner: runner).prepare(source: $1, target: $2, projectId: $3) },
            finalize: { try await MergeFinisher(root: $0, runner: runner).finalize($1, settings: ValidationSettings(), healthProbe: nil) },
            abort: { try await MergeFinisher(root: $0, runner: runner).abort($1) }
        )
    }
}

public struct WorktreeApply: Sendable {
    public let operations: WorktreeApplyOperations

    public init(operations: WorktreeApplyOperations = .live()) {
        self.operations = operations
    }

    public static func commitMessage(jobID: String) -> String { "Alethe orchestrator: \(jobID)" }

    public func preview(worktree: URL, agentID: String) async throws -> WorktreeApplyPreview {
        let id = try GitWorktrees.sanitizeAgentId(agentID)
        let root = try await operations.mainRoot(worktree)
        guard let target = try await operations.currentBranch(root), !target.isEmpty else {
            throw WorktreeApplyError.detachedTarget
        }
        let source = GitWorktrees.branchName(for: id)
        guard source != target else { throw WorktreeApplyError.sameBranch(target) }
        let pending = try await operations.pendingChanges(root, id)
        let committed = await operations.committedFiles(root, source, target)
        return WorktreeApplyPreview(root: root, agentID: id, source: source, target: target,
                                    pending: pending, committed: committed)
    }

    public func run(_ preview: WorktreeApplyPreview, projectID: String? = nil,
                    progress: @escaping @Sendable (WorktreeApplyStep) -> Void = { _ in }) async throws -> WorktreeApplyResult {
        let ops = operations
        let (root, id, source, target) = (preview.root, preview.agentID, preview.source, preview.target)
        var result = WorktreeApplyResult(outcome: .cancelled)
        do {
            guard !Task.isCancelled else { return result }
            progress(.committing)
            let message = Self.commitMessage(jobID: id)
            result.committedPending = try await Self.shielded { try await ops.commitPending(root, id, message) }

            guard !Task.isCancelled else { return result }
            progress(.fetching)
            try? await Self.shielded { try await ops.fetchBranch(root, id) }

            guard !Task.isCancelled else { return result }
            progress(.analyzing)
            let analysis = try await ops.analyze(root, source, target)
            result.analysis = analysis

            guard !Task.isCancelled else { return result }
            progress(.preparing)
            let environment = try await ops.prepare(root, source, target, projectID)
            result.environment = environment
            let handle = MergeEnvHandle(id: environment.id, source: source, target: target,
                                        conflictPaths: environment.conflicts.map(\.path))
            if !analysis.clean || !environment.clean {
                result.outcome = .conflicted(environmentID: environment.id)
                return result
            }
            guard !Task.isCancelled else {
                try? await Self.shielded { try await ops.abort(root, handle) }
                result.environment = nil
                return result
            }

            progress(.finalizing)
            let finished = try await Self.shielded { try await ops.finalize(root, handle) }
            if finished.merged {
                result.outcome = .applied
            } else if finished.stage == .nothingToIntegrate {
                try? await Self.shielded { try await ops.abort(root, handle) }
                result.environment = nil
                result.outcome = .nothingToApply
            } else {
                result.outcome = .notMerged(environmentID: environment.id, stage: finished.stage, output: finished.output)
            }
            return result
        } catch {
            if Task.isCancelled { return WorktreeApplyResult(outcome: .cancelled, committedPending: result.committedPending) }
            throw error
        }
    }

    static func shielded<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await Task.detached { try await operation() }.value
    }
}
