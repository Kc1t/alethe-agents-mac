import AletheGit
import Foundation

public struct ConflictEnvironment: Sendable, Hashable, Codable {
    public var id: String
    public var path: URL
    public var branch: String
    public var clean: Bool
    public var conflicts: [ConflictFile]
    public var promptPath: URL?
}

public struct MergeMeta: Sendable, Hashable, Codable {
    public var id: String
    public var source: String
    public var target: String
    public var projectId: String?
    public var conflictPaths: [String]
    public var stage: MergeCenterStage?
    public var lastValidation: ValidationReport?
    public var contractWarnings: [ContractWarning]?

    public init(id: String, source: String, target: String, projectId: String? = nil, conflictPaths: [String],
                stage: MergeCenterStage? = nil, lastValidation: ValidationReport? = nil,
                contractWarnings: [ContractWarning]? = nil) {
        self.id = id
        self.source = source
        self.target = target
        self.projectId = projectId
        self.conflictPaths = conflictPaths
        self.stage = stage
        self.lastValidation = lastValidation
        self.contractWarnings = contractWarnings
    }
}

public enum RebaseOutcome: Sendable, Hashable {
    case reconciled
    case conflicted([ConflictFile])
    case failed(String)

    public var stage: String {
        if case .reconciled = self {
            return "rebase_ok"
        }
        if case .conflicted = self {
            return "rebase_conflict"
        }
        return "rebase_failed"
    }

    public var output: String {
        if case .reconciled = self {
            return "Reconciled with the updated target — ready to reintegrate."
        }
        if case .conflicted(let conflicts) = self {
            return "Conflicts while reconciling with the updated target: \(conflicts.map(\.path).joined(separator: ", "))"
        }
        if case .failed(let message) = self {
            return message.isEmpty ? "rebase_failed" : message
        }
        preconditionFailure("Unknown rebase outcome")
    }
}

public enum MergePrepareStep: String, Sendable, Hashable, CaseIterable {
    case creatingEnvironment, merging, listingConflicts, writingPrompt, fetchingTarget, reconciling, aborting
}

public enum ConflictResolutionError: Error, Equatable, Sendable {
    case invalidEnvironmentID(String)
    case environmentNotFound(String)
    case invalidMetadata(String)
}

public struct ConflictResolution: Sendable {
    public static let promptFileName = "ALETHE_CONFLICT.md"

    public let root: URL
    public let runner: GitRunner

    public init(root: URL, runner: GitRunner = GitRunner()) {
        self.root = root
        self.runner = runner
    }

    public static func branchName(id: String) -> String { "alethe/merge-\(id)" }

    public func environmentDirectory(id: String) -> URL {
        MergeAnalyzer.mergeEnvsDirectory(root: root).appendingPathComponent(id, isDirectory: true)
    }

    public func metaURL(id: String) -> URL {
        MergeAnalyzer.mergeEnvsDirectory(root: root).appendingPathComponent("\(id).json")
    }

    public func prepare(
        source: String,
        target: String,
        projectId: String? = nil,
        progress: (@Sendable (MergePrepareStep) -> Void)? = nil
    ) async throws -> ConflictEnvironment {
        let analyzer = MergeAnalyzer(root: root, runner: runner)
        try await analyzer.ensureBranch(source)
        try await analyzer.ensureBranch(target)

        let id = Self.newID()
        let env = environmentDirectory(id: id)
        let branch = Self.branchName(id: id)
        try FileManager.default.createDirectory(
            at: MergeAnalyzer.mergeEnvsDirectory(root: root), withIntermediateDirectories: true)

        do {
            progress?(.creatingEnvironment)
            _ = try await runner.run(["worktree", "add", "-b", branch, env.path, target], in: root)
            progress?(.merging)
            let merge = try await runner.run(
                ["merge", "--no-commit", "--no-ff", source], in: env, allowedExitCodes: [0, 1])
            let clean = merge.exitCode == 0
            var conflicts: [ConflictFile] = []
            if !clean {
                progress?(.listingConflicts)
                conflicts = try await analyzer.unmergedFiles(in: env).map { ConflictFile(path: $0) }
            }
            let meta = MergeMeta(
                id: id, source: source, target: target, projectId: projectId,
                conflictPaths: conflicts.map(\.path))
            try writeMeta(meta)

            var promptPath: URL?
            if !clean {
                progress?(.writingPrompt)
                let url = env.appendingPathComponent(Self.promptFileName)
                try Data(Self.buildPrompt(meta: meta, conflicts: conflicts).utf8).write(to: url)
                promptPath = url
            }
            return ConflictEnvironment(
                id: id, path: env, branch: branch, clean: clean, conflicts: conflicts, promptPath: promptPath)
        } catch {
            await destroy(id: id)
            throw error
        }
    }

    public func conflicts(id: String) async throws -> [ConflictFile] {
        let env = try existingEnvironment(id: id)
        return try await MergeAnalyzer(root: root, runner: runner).unmergedFiles(in: env).map { ConflictFile(path: $0) }
    }

    public func inProgress() -> [MergeSessionSummary] {
        let fm = FileManager.default
        let dir = MergeAnalyzer.mergeEnvsDirectory(root: root)
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        let found = entries.compactMap { url -> (MergeSessionSummary, Date)? in
            guard url.pathExtension == "json" else { return nil }
            let id = url.deletingPathExtension().lastPathComponent
            guard (try? Self.validateID(id)) != nil, (try? existingEnvironment(id: id)) != nil,
                  let meta = try? readMeta(id: id), meta.id == id else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (MergeSessionSummary(meta: meta), date)
        }
        return found.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }.map(\.0)
    }

    public func resume(id: String) async throws -> (environment: ConflictEnvironment, meta: MergeMeta) {
        let env = try existingEnvironment(id: id)
        let meta = try readMeta(id: id)
        let conflicts = try await MergeAnalyzer(root: root, runner: runner).unmergedFiles(in: env).map { ConflictFile(path: $0) }
        let prompt = env.appendingPathComponent(Self.promptFileName)
        let environment = ConflictEnvironment(
            id: id, path: env, branch: Self.branchName(id: id), clean: meta.conflictPaths.isEmpty,
            conflicts: conflicts, promptPath: FileManager.default.fileExists(atPath: prompt.path) ? prompt : nil)
        return (environment, meta)
    }

    public func updateMeta(id: String, _ change: (inout MergeMeta) -> Void) throws {
        _ = try existingEnvironment(id: id)
        var meta = try readMeta(id: id)
        change(&meta)
        try writeMeta(meta)
    }

    public func rebaseOntoTarget(
        id: String,
        progress: (@Sendable (MergePrepareStep) -> Void)? = nil
    ) async throws -> RebaseOutcome {
        let env = try existingEnvironment(id: id)
        var meta = try readMeta(id: id)

        progress?(.fetchingTarget)
        _ = try await runner.run(["fetch", root.path, meta.target], in: env)
        progress?(.reconciling)
        let reconcile = try await runner.run(
            ["merge", "--no-edit", "FETCH_HEAD"], in: env, allowedExitCodes: Set(Int32(0)...Int32(255)))
        if reconcile.exitCode == 0 { return .reconciled }

        let unresolved = (try? await MergeAnalyzer(root: root, runner: runner).unmergedFiles(in: env)) ?? []
        if !unresolved.isEmpty {
            let conflicts = unresolved.map { ConflictFile(path: $0) }
            progress?(.writingPrompt)
            try? Data(Self.buildPrompt(meta: meta, conflicts: conflicts).utf8)
                .write(to: env.appendingPathComponent(Self.promptFileName))
            meta.conflictPaths = conflicts.map(\.path)
            try? writeMeta(meta)
            return .conflicted(conflicts)
        }

        progress?(.aborting)
        _ = try? await runner.run(["merge", "--abort"], in: env, allowedExitCodes: Set(Int32(0)...Int32(255)))
        return .failed(reconcile.errorText)
    }

    public func preflightAbort(id: String) async throws {
        let env = try existingEnvironment(id: id)
        try await safeAbort(["merge", "--abort"], in: env)
        try await safeAbort(["rebase", "--abort"], in: env)
    }

    public func abort(id: String) async throws {
        try Self.validateID(id)
        await destroy(id: id)
    }

    public static func buildPrompt(meta: MergeMeta, conflicts: [ConflictFile]) -> String {
        var lines = [
            "# Merge conflict resolution (Alethe)",
            "",
            "Merge from `\(meta.source)` into `\(meta.target)`. This directory is an EPHEMERAL environment for this integration only.",
            "",
            "## Rules (locked scope)",
            "- Resolve ONLY the conflicts listed below. Nothing beyond that.",
            "- NEVER implement features, change requirements, or change architecture.",
            "- Preserve the intent of BOTH branches; confirm nothing was lost.",
            "- When done, just save the resolved files (no commit — Alethe commits after validation).",
            "",
            "## Conflicted files",
        ]
        for conflict in conflicts {
            lines.append("- `\(conflict.path)` — \(conflict.class.variantName): \(conflict.class.strategy)")
        }
        lines.append("")
        lines.append("Use `git diff` in this directory to see the markers (`<<<<<<<`/`>>>>>>>`).")
        return lines.joined(separator: "\n")
    }

    public static func agentInstruction() -> String {
        "Read \(promptFileName) in this directory and resolve the listed merge conflicts following its rules."
    }

    public static func validateID(_ id: String) throws {
        let allowed = id.unicodeScalars.allSatisfy {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "_"
        }
        guard !id.isEmpty, allowed else { throw ConflictResolutionError.invalidEnvironmentID(id) }
    }

    public func readMeta(id: String) throws -> MergeMeta {
        guard let data = try? Data(contentsOf: metaURL(id: id)) else {
            throw ConflictResolutionError.environmentNotFound(id)
        }
        do { return try JSONDecoder().decode(MergeMeta.self, from: data) } catch {
            throw ConflictResolutionError.invalidMetadata(String(describing: error))
        }
    }

    func writeMeta(_ meta: MergeMeta) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meta).write(to: metaURL(id: meta.id), options: .atomic)
    }

    private func existingEnvironment(id: String) throws -> URL {
        try Self.validateID(id)
        let env = environmentDirectory(id: id)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: env.path, isDirectory: &isDir), isDir.boolValue else {
            throw ConflictResolutionError.environmentNotFound(id)
        }
        return env
    }

    private func safeAbort(_ args: [String], in env: URL) async throws {
        do {
            _ = try await runner.run(args, in: env)
        } catch GitError.commandFailed(let code, let stderr) {
            let lower = stderr.lowercased()
            if lower.contains("no merge") || lower.contains("no rebase") { return }
            throw GitError.commandFailed(exitCode: code, stderr: stderr)
        }
    }

    private func destroy(id: String) async {
        let env = environmentDirectory(id: id)
        let root = root, runner = runner, meta = metaURL(id: id)
        await Task.detached {
            _ = try? await runner.run(["merge", "--abort"], in: env, allowedExitCodes: Set(Int32(0)...Int32(255)))
            _ = try? await runner.run(["worktree", "remove", "--force", "--force", env.path], in: root)
            try? FileManager.default.removeItem(at: env)
            _ = try? await runner.run(["worktree", "prune"], in: root)
            _ = try? await runner.run(["branch", "-D", Self.branchName(id: id)], in: root)
            try? FileManager.default.removeItem(at: meta)
        }.value
    }

    static func newID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10)).lowercased()
    }
}
