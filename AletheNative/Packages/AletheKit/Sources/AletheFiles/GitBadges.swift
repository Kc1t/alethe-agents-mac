import AletheGit
import Foundation

public enum GitBadge: String, Hashable, Sendable, CaseIterable {
    case conflict, modified, stagedModified, added, untracked, renamed, deleted

    public var priority: Int {
        if case .conflict = self { return 100 }
        else if case .modified = self { return 80 }
        else if case .stagedModified = self { return 70 }
        else if case .added = self { return 60 }
        else if case .untracked = self { return 50 }
        else if case .renamed = self { return 40 }
        else { return 30 }
    }

    public var letter: String {
        if case .conflict = self { return "!" }
        else if case .modified = self { return "M" }
        else if case .stagedModified = self { return "M" }
        else if case .added = self { return "A" }
        else if case .untracked = self { return "U" }
        else if case .renamed = self { return "R" }
        else { return "D" }
    }
}

public struct GitBadgeIndex: Hashable, Sendable {
    public let repoRoot: String
    public private(set) var files: [String: GitBadge] = [:]
    public private(set) var folders: [String: GitBadge] = [:]

    public init(status: GitStatus, repoRoot: URL) {
        self.repoRoot = Self.normalize(repoRoot)
        for entry in status.entries {
            guard let badge = Self.badge(for: entry) else { continue }
            register(entry.path, badge)
        }
    }

    static func badge(for entry: GitStatusEntry) -> GitBadge? {
        if entry.kind == .ignored { return nil }
        if entry.kind == .unmerged { return .conflict }
        if entry.kind == .untracked { return .untracked }
        let staged = stagedBadge(for: entry)
        let unstaged = unstagedBadge(for: entry)
        return [staged, unstaged].compactMap { $0 }.max { $0.priority < $1.priority }
    }

    private static func stagedBadge(for entry: GitStatusEntry) -> GitBadge? {
        if entry.index == .added { return .added }
        if entry.index == .deleted { return .deleted }
        if entry.index == .renamed || entry.index == .copied { return .renamed }
        return entry.index == nil ? nil : .stagedModified
    }

    private static func unstagedBadge(for entry: GitStatusEntry) -> GitBadge? {
        if entry.worktree == .deleted { return .deleted }
        if entry.worktree == .renamed || entry.worktree == .copied { return .renamed }
        return entry.worktree == nil ? nil : .modified
    }

    private mutating func register(_ path: String, _ badge: GitBadge) {
        var key = path.replacingOccurrences(of: "\\", with: "/").lowercased()
        while key.hasPrefix("/") { key.removeFirst() }
        while key.hasSuffix("/") { key.removeLast() }
        if files[key].map({ badge.priority > $0.priority }) ?? true { files[key] = badge }
        var parts = key.split(separator: "/").dropLast()
        folders[""] = Self.stronger(folders[""], badge)
        while !parts.isEmpty {
            let folder = parts.joined(separator: "/")
            folders[folder] = Self.stronger(folders[folder], badge)
            parts = parts.dropLast()
        }
        if path.hasSuffix("/") { folders[key] = Self.stronger(folders[key], badge) }
    }

    private static func stronger(_ current: GitBadge?, _ new: GitBadge) -> GitBadge {
        guard let current else { return new }
        return new.priority > current.priority ? new : current
    }

    static func normalize(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    public func badge(for url: URL, isDirectory: Bool) -> GitBadge? {
        let path = Self.normalize(url)
        if path == repoRoot { return isDirectory ? folders[""] : nil }
        guard path.hasPrefix(repoRoot + "/") else { return nil }
        let relative = String(path.dropFirst(repoRoot.count + 1))
        return isDirectory ? folders[relative] : files[relative]
    }
}
