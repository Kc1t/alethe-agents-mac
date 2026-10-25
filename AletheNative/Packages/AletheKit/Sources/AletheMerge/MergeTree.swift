import Foundation

public enum MergeTreeGrouping: String, Sendable, Hashable, Codable, CaseIterable {
    case folder, `class`
}

public struct MergeTreeGroup: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var files: [ConflictFile]

    public init(id: String, title: String, files: [ConflictFile]) {
        self.id = id
        self.title = title
        self.files = files
    }
}

public enum MergeTree {
    public static func folder(of path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard let slash = normalized.lastIndex(of: "/") else { return "" }
        return String(normalized[..<slash])
    }

    public static func fileName(of path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.split(separator: "/").last.map(String.init) ?? normalized
    }

    public static func groups(_ conflicts: [ConflictFile], by grouping: MergeTreeGrouping) -> [MergeTreeGroup] {
        var seen: Set<String> = []
        let unique = conflicts.filter { seen.insert($0.path).inserted }
        switch grouping {
        case .folder:
            let byFolder = Dictionary(grouping: unique) { folder(of: $0.path) }
            return byFolder.keys.sorted().map { key in
                MergeTreeGroup(id: key, title: key.isEmpty ? "." : key,
                               files: byFolder[key]!.sorted { $0.path < $1.path })
            }
        case .class:
            let byClass = Dictionary(grouping: unique, by: \.class)
            return byClass.keys.sorted { $0.variantName < $1.variantName }.map { key in
                MergeTreeGroup(id: key.rawValue, title: key.variantName,
                               files: byClass[key]!.sorted { $0.path < $1.path })
            }
        }
    }
}

public struct MergeSessionSummary: Sendable, Hashable, Identifiable {
    public var meta: MergeMeta
    public var stage: MergeCenterStage
    public var id: String { meta.id }
    public var conflicts: [ConflictFile] { meta.conflictPaths.map { ConflictFile(path: $0) } }

    public init(meta: MergeMeta) {
        self.meta = meta
        stage = MergeResumePoint.stage(recorded: meta.stage, conflictPaths: meta.conflictPaths)
    }
}

public enum MergeResumePoint {
    public static func stage(recorded: MergeCenterStage?, conflictPaths: [String], unresolved: [String]? = nil) -> MergeCenterStage {
        let base: MergeCenterStage
        if let recorded, recorded != .analyze {
            base = recorded
        } else {
            base = conflictPaths.isEmpty ? .validate : .prepare
        }
        if let unresolved, !unresolved.isEmpty { return .prepare }
        return base
    }
}
