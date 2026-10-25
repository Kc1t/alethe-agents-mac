import AletheGit
import Foundation

struct JobWorkspace: Hashable, Sendable {
    var jobID: String
    var cwd: String
    var worktree: String?
}

extension OrchestratorCore {
    func workspaces(for ids: [String], request: DelegateRequest) async throws(OrchestratorToolError) -> [JobWorkspace] {
        guard request.isolate else {
            return ids.map { JobWorkspace(jobID: $0, cwd: request.cwd, worktree: nil) }
        }
        return try await Self.makeWorktrees(for: ids, repo: request.cwd, worktrees: configuration.worktrees)
    }

    @concurrent
    static func makeWorktrees(for ids: [String], repo: String, worktrees: GitWorktrees) async throws(OrchestratorToolError)
        -> [JobWorkspace] {
        let folder = URL(fileURLWithPath: repo, isDirectory: true)
        var made: [JobWorkspace] = []
        for id in ids {
            do {
                let info = try await worktrees.provision(repo: folder, agentId: id, mode: .gitWorktree)
                made.append(JobWorkspace(jobID: id, cwd: info.path, worktree: info.path))
            } catch {
                await removeWorktrees(made, repo: repo, worktrees: worktrees)
                throw OrchestratorToolError("isolate needs a git repository at \(repo): \(describe(error, jobID: id))")
            }
        }
        return made
    }

    @concurrent
    static func removeWorktrees(_ workspaces: [JobWorkspace], repo: String, worktrees: GitWorktrees) async {
        let folder = URL(fileURLWithPath: repo, isDirectory: true)
        let isolated = workspaces.filter { $0.worktree != nil }
        guard !isolated.isEmpty, let root = try? await worktrees.mainRepositoryRoot(folder) else { return }
        for workspace in isolated {
            try? await worktrees.remove(repo: folder, agentId: workspace.jobID, force: true)
            _ = try? await worktrees.runner.run(["branch", "-D", GitWorktrees.branchName(for: workspace.jobID)], in: root)
        }
    }

    private static func describe(_ error: any Error, jobID: String) -> String {
        if case GitError.notARepository = error {
            return "not a git repository"
        } else if case GitError.gitMissing = error {
            return "git not available"
        } else if case GitError.commandFailed(_, let stderr) = error {
            return stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if case GitWorktreeError.exists = error {
            return "a worktree already exists for \(jobID)"
        } else {
            return String(describing: error)
        }
    }
}
