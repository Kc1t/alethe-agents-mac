import Foundation

public struct SessionSnapshot: Equatable, Hashable, Sendable {
    public var id: String
    public var modifiedAt: Date

    public init(id: String, modifiedAt: Date) {
        self.id = id
        self.modifiedAt = modifiedAt
    }
}

public enum SessionPaths {
    public static func normalize(_ path: String) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return "" }
        return (trimmed as NSString).resolvingSymlinksInPath
    }
}

public enum ClaudeSessions {
    public static func projectFolderName(for cwd: String) -> String {
        var path = cwd
        while path.count > 1, path.hasSuffix("/") || path.hasSuffix("\\") { path.removeLast() }
        return String(path.map { ":\\/.".contains($0) ? "-" : $0 })
    }

    public static func snapshot(cwd: String, homeDirectory: String = NSHomeDirectory(),
                                fileManager: FileManager = .default) -> [SessionSnapshot] {
        let projects = "\(homeDirectory)/.claude/projects"
        guard let folders = try? fileManager.contentsOfDirectory(atPath: projects) else { return [] }
        let names = Set([cwd, SessionPaths.normalize(cwd)].filter { !$0.isEmpty }.map(projectFolderName(for:)))
        let folder = folders.first(where: names.contains)
            ?? folders.first { folder in names.contains { $0.caseInsensitiveCompare(folder) == .orderedSame } }
        guard let folder else { return [] }
        let directory = "\(projects)/\(folder)"
        let files = (try? fileManager.contentsOfDirectory(atPath: directory)) ?? []
        return files.filter { $0.hasSuffix(".jsonl") }.compactMap { name in
            let path = "\(directory)/\(name)"
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            let modified = attributes?[.modificationDate] as? Date ?? .distantPast
            return SessionSnapshot(id: String(name.dropLast(".jsonl".count)), modifiedAt: modified)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }
}

public enum CodexSessions {
    public static func snapshot(cwd: String, homeDirectory: String = NSHomeDirectory(),
                                fileManager: FileManager = .default) -> [SessionSnapshot] {
        let target = SessionPaths.normalize(cwd)
        guard !target.isEmpty else { return [] }
        let root = "\(homeDirectory)/.codex/sessions"
        guard let enumerator = fileManager.enumerator(atPath: root) else { return [] }
        var seen = Set<String>()
        var sessions: [SessionSnapshot] = []
        while let relative = enumerator.nextObject() as? String {
            guard relative.hasSuffix(".jsonl") else { continue }
            let path = "\(root)/\(relative)"
            guard let meta = sessionMeta(atPath: path),
                  SessionPaths.normalize(meta.cwd) == target,
                  seen.insert(meta.id).inserted else { continue }
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            sessions.append(SessionSnapshot(id: meta.id, modifiedAt: attributes?[.modificationDate] as? Date ?? .distantPast))
        }
        return sessions.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    static func sessionMeta(atPath path: String) -> (id: String, cwd: String)? {
        guard let line = firstLine(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let id = payload["id"] as? String, !id.isEmpty,
              let cwd = payload["cwd"] as? String else { return nil }
        return (id, cwd)
    }

    private static func firstLine(atPath path: String, limit: Int = 1 << 20) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var line = Data()
        while line.count < limit {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            if let newline = chunk.firstIndex(of: UInt8(ascii: "\n")) {
                line.append(chunk[chunk.startIndex..<newline])
                return line
            }
            line.append(chunk)
        }
        return line.isEmpty || line.count >= limit ? nil : line
    }
}

public struct SessionClaims: Sendable {
    private struct Key: Hashable, Sendable {
        var agent: String
        var cwd: String
    }

    private var owners: [Key: [String: String]] = [:]

    public init() {}

    private static func key(_ agent: AgentKind, _ cwd: String) -> Key {
        Key(agent: agent.rawValue, cwd: SessionPaths.normalize(cwd))
    }

    public mutating func register(_ agent: AgentKind, cwd: String, sessionID: String, owner: String) {
        owners[Self.key(agent, cwd), default: [:]][sessionID] = owner
    }

    public func isClaimed(_ agent: AgentKind, cwd: String, sessionID: String, excluding owner: String? = nil) -> Bool {
        guard let holder = owners[Self.key(agent, cwd)]?[sessionID] else { return false }
        return holder != owner
    }

    public mutating func claimDiscovered(_ agent: AgentKind, cwd: String, before: Set<String>,
                                         sessions: [SessionSnapshot], owner: String) -> SessionSnapshot? {
        let key = Self.key(agent, cwd)
        let held = owners[key] ?? [:]
        let candidates = sessions.filter { !before.contains($0.id) && held[$0.id] == nil }
        guard candidates.count == 1, let found = candidates.first else { return nil }
        owners[key, default: [:]][found.id] = owner
        return found
    }

    public mutating func release(owner: String) {
        for key in Array(owners.keys) {
            owners[key] = owners[key]?.filter { $0.value != owner }
            if owners[key]?.isEmpty == true { owners.removeValue(forKey: key) }
        }
    }
}
