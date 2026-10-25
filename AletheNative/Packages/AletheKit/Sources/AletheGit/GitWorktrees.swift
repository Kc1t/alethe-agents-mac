import Foundation

public enum WorktreeMode: String, Codable, Sendable, CaseIterable {
    case gitWorktree
    case localCopy
}

public struct WorktreeSettings: Codable, Equatable, Sendable {
    public var autoWorktree: Bool
    public var worktreeMode: WorktreeMode?

    public init(autoWorktree: Bool = false, worktreeMode: WorktreeMode? = nil) {
        self.autoWorktree = autoWorktree
        self.worktreeMode = worktreeMode
    }

    public var effectiveMode: WorktreeMode { worktreeMode ?? .gitWorktree }

    public func agentIdForNewTerminal(isAgent: Bool, terminalId: String) -> String? {
        guard autoWorktree, isAgent, (try? GitWorktrees.sanitizeAgentId(terminalId)) != nil else { return nil }
        return terminalId.trimmingCharacters(in: .whitespaces)
    }
}

public struct WorktreeInfo: Equatable, Sendable, Codable {
    public var agentId: String
    public var path: String
    public var branch: String
    public var mode: WorktreeMode
}

public struct GitWorktreeEntry: Equatable, Sendable {
    public var path: String
    public var head: String?
    public var branch: String?
    public var isBare = false
    public var isDetached = false
    public var isLocked = false
    public var lockReason: String?
    public var isPrunable = false
    public var prunableReason: String?

    public init(path: String) { self.path = path }

    public var agentId: String? {
        guard let branch, branch.hasPrefix(GitWorktrees.branchPrefix) else { return nil }
        let id = String(branch.dropFirst(GitWorktrees.branchPrefix.count))
        return id.isEmpty ? nil : id
    }
}

public struct WorktreePendingChange: Equatable, Sendable {
    public var path: String
    public var status: String
}

public enum GitWorktreeError: Error, Equatable, Sendable {
    case invalidAgentId
    case exists
    case notFound
    case invalidPath
    case adminLocked(reason: String)
}

public struct GitWorktrees: Sendable {
    public static let branchPrefix = "alethe/agent-"
    public static let defaultCommitMessage = "Agent work (auto-commit before integration)"

    public let runner: GitRunner

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    public static func sanitizeAgentId(_ agentId: String) throws -> String {
        let trimmed = agentId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") })
        else { throw GitWorktreeError.invalidAgentId }
        return trimmed
    }

    public static func branchName(for agentId: String) -> String { branchPrefix + agentId }

    public static func worktreesBase(_ root: URL) -> URL {
        root.appendingPathComponent(".alethe", isDirectory: true).appendingPathComponent("worktrees", isDirectory: true)
    }

    public static func detectMode(_ directory: URL) -> WorktreeMode? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path, isDirectory: &isDirectory)
        else { return nil }
        return isDirectory.boolValue ? .localCopy : .gitWorktree
    }

    public static func parsePorcelain(_ output: String) -> [GitWorktreeEntry] {
        var entries: [GitWorktreeEntry] = []
        var current: GitWorktreeEntry?
        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\0" })
        for raw in lines {
            let line = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.isEmpty {
                if let entry = current { entries.append(entry) }
                current = nil
                continue
            }
            let key: Substring, value: String?
            if let space = line.firstIndex(of: " ") {
                key = line[..<space]
                value = String(line[line.index(after: space)...])
            } else {
                key = Substring(line)
                value = nil
            }
            if key == "worktree" {
                if let entry = current { entries.append(entry) }
                current = GitWorktreeEntry(path: value ?? "")
                continue
            }
            guard current != nil else { continue }
            if key == "HEAD" {
                current?.head = value
            } else if key == "branch" {
                current?.branch = value.map { $0.hasPrefix("refs/heads/") ? String($0.dropFirst("refs/heads/".count)) : $0 }
            } else if key == "bare" {
                current?.isBare = true
            } else if key == "detached" {
                current?.isDetached = true
            } else if key == "locked" {
                current?.isLocked = true
                current?.lockReason = value
            } else if key == "prunable" {
                current?.isPrunable = true
                current?.prunableReason = value
            }
        }
        if let entry = current { entries.append(entry) }
        return entries
    }

    public static func isRealWork(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix(".planning/") && !path.hasPrefix(".opencode/") && path != "opencode.json"
    }

    public static func parsePendingChanges(_ output: String) -> [WorktreePendingChange] {
        output.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let chars = Array(line)
            let status = String(chars.prefix(2)).trimmingCharacters(in: .whitespaces)
            let path = chars.count > 3 ? String(chars[3...]).trimmingCharacters(in: .whitespaces) : ""
            return isRealWork(path) ? WorktreePendingChange(path: path, status: status) : nil
        }
    }

    public func mainRepositoryRoot(_ path: URL) async throws -> URL {
        let output = try await runner.run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: path)
        let common = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !common.isEmpty else { throw GitError.notARepository }
        return URL(fileURLWithPath: common, isDirectory: true).resolvingSymlinksInPath()
            .deletingLastPathComponent().standardizedFileURL
    }

    private func environment(_ repo: URL, _ agentId: String) async throws -> (root: URL, id: String, dir: URL) {
        let root = try await mainRepositoryRoot(repo)
        let id = try Self.sanitizeAgentId(agentId)
        return (root, id, Self.worktreesBase(root).appendingPathComponent(id, isDirectory: true))
    }

    public func provision(repo: URL, agentId: String, mode: WorktreeMode) async throws -> WorktreeInfo {
        let (root, id, dest) = try await environment(repo, agentId)
        try FileManager.default.createDirectory(at: Self.worktreesBase(root), withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: dest.path) else { throw GitWorktreeError.exists }
        let branch = Self.branchName(for: id)
        if mode == .gitWorktree {
            _ = try await runner.run(["worktree", "add", "-b", branch, dest.path, "HEAD"], in: root)
        } else {
            _ = try await runner.run(["clone", "--local", "--", root.path, dest.path], in: root)
            _ = try await runner.run(["checkout", "-b", branch], in: dest)
        }
        return WorktreeInfo(agentId: id, path: dest.path, branch: branch, mode: mode)
    }

    public func list(repo: URL) async throws -> [WorktreeInfo] {
        let root = try await mainRepositoryRoot(repo)
        let base = Self.worktreesBase(root)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.isDirectoryKey], options: []
        )) ?? []
        var result: [WorktreeInfo] = []
        for dir in children {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let mode = Self.detectMode(dir) else { continue }
            let head = try? await runner.run(["rev-parse", "--abbrev-ref", "HEAD"], in: dir)
            let branch = head?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            result.append(WorktreeInfo(agentId: dir.lastPathComponent, path: dir.path, branch: branch, mode: mode))
        }
        return result.sorted { $0.agentId < $1.agentId }
    }

    public func gitWorktrees(repo: URL) async throws -> [GitWorktreeEntry] {
        let root = try await mainRepositoryRoot(repo)
        return Self.parsePorcelain(try await runner.run(["worktree", "list", "--porcelain"], in: root).text)
    }

    public func remove(repo: URL, agentId: String, force: Bool) async throws {
        let (root, _, dest) = try await environment(repo, agentId)
        guard FileManager.default.fileExists(atPath: dest.path) else { throw GitWorktreeError.notFound }
        let base = Self.worktreesBase(root).resolvingSymlinksInPath().path + "/"
        let resolved = dest.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(base) else { throw GitWorktreeError.invalidPath }
        if Self.detectMode(dest) == .gitWorktree {
            if let reason = Self.adminLockReason(dest) { throw GitWorktreeError.adminLocked(reason: reason) }
            _ = try await runner.run(["worktree", "remove"] + (force ? ["--force"] : []) + [resolved.path], in: root)
        } else {
            try FileManager.default.removeItem(at: resolved)
        }
    }

    public func lock(repo: URL, agentId: String, reason: String? = nil) async throws {
        let (root, _, dest) = try await environment(repo, agentId)
        guard FileManager.default.fileExists(atPath: dest.path) else { throw GitWorktreeError.notFound }
        var args = ["worktree", "lock"]
        if let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            args += ["--reason", reason]
        }
        _ = try await runner.run(args + [dest.path], in: root)
    }

    public func unlock(repo: URL, agentId: String) async throws {
        let (root, _, dest) = try await environment(repo, agentId)
        guard FileManager.default.fileExists(atPath: dest.path) else { throw GitWorktreeError.notFound }
        _ = try await runner.run(["worktree", "unlock", dest.path], in: root)
    }

    public func fetchBranch(repo: URL, agentId: String) async throws {
        let (root, id, dir) = try await environment(repo, agentId)
        let mode = Self.detectMode(dir)
        if mode == .localCopy {
            let branch = Self.branchName(for: id)
            _ = try await runner.run(["fetch", dir.path, "+refs/heads/\(branch):refs/heads/\(branch)"], in: root)
        } else if mode == .gitWorktree {
            return
        } else {
            throw GitWorktreeError.notFound
        }
    }

    public func pendingChanges(repo: URL, agentId: String) async throws -> [WorktreePendingChange] {
        let dir = try await existingEnvironment(repo, agentId)
        return Self.parsePendingChanges(try await runner.run(["status", "--porcelain"], in: dir).text)
    }

    @discardableResult
    public func commitPending(repo: URL, agentId: String, message: String = GitWorktrees.defaultCommitMessage) async throws -> Bool {
        let dir = try await existingEnvironment(repo, agentId)
        let changes = Self.parsePendingChanges(try await runner.run(["status", "--porcelain"], in: dir).text)
        guard !changes.isEmpty else { return false }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultCommitMessage : message
        _ = try await runner.run(["add", "--"] + changes.map(\.path), in: dir)
        _ = try await runner.run(["commit", "-m", text], in: dir)
        return true
    }

    @discardableResult
    public func cleanup(repo: URL) async throws -> [String] {
        let root = try await mainRepositoryRoot(repo)
        let base = Self.worktreesBase(root)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.isDirectoryKey], options: []
        )) ?? []
        var removed: [String] = []
        for dir in children where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            guard Self.detectMode(dir) == nil, (try? Self.sanitizeAgentId(dir.lastPathComponent)) != nil else { continue }
            try FileManager.default.removeItem(at: dir)
            removed.append(dir.lastPathComponent)
        }
        _ = try await runner.run(["worktree", "prune"], in: root)
        return removed.sorted()
    }

    private func existingEnvironment(_ repo: URL, _ agentId: String) async throws -> URL {
        let (_, _, dir) = try await environment(repo, agentId)
        guard Self.detectMode(dir) != nil else { throw GitWorktreeError.notFound }
        return dir
    }

    static func adminLockReason(_ worktree: URL) -> String? {
        guard let pointer = try? String(contentsOf: worktree.appendingPathComponent(".git"), encoding: .utf8),
              let line = pointer.split(separator: "\n").first, line.hasPrefix("gitdir:") else { return nil }
        let gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let adminDir = gitdir.hasPrefix("/") ? URL(fileURLWithPath: gitdir) : worktree.appendingPathComponent(gitdir)
        let locked = adminDir.appendingPathComponent("locked")
        guard FileManager.default.fileExists(atPath: locked.path) else { return nil }
        let reason = ((try? String(contentsOf: locked, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? "no reason given" : reason
    }
}
