import AletheGit
import Foundation
import Observation

public struct FileNode: Hashable, Sendable, Identifiable {
    public var url: URL
    public var name: String
    public var isDirectory: Bool
    public var size: Int?

    public var id: URL { url }

    public init(url: URL, name: String, isDirectory: Bool, size: Int? = nil) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
    }

    public var iconName: String {
        isDirectory ? FileIcons.folderSymbol : FileIcons.symbolName(forFileName: name)
    }

    public var paneKind: FilePaneKind? {
        isDirectory ? nil : FilePaneKind.forFile(url.path)
    }
}

public struct FileTreeFilter: Hashable, Sendable {
    public var showDotfiles: Bool
    public var hiddenNames: Set<String>

    public init(showDotfiles: Bool = true, hiddenNames: Set<String> = [".DS_Store"]) {
        self.showDotfiles = showDotfiles
        self.hiddenNames = hiddenNames
    }

    public static let `default` = FileTreeFilter()

    public func includes(_ name: String) -> Bool {
        if hiddenNames.contains(name) { return false }
        if !showDotfiles, name.hasPrefix(".") { return false }
        return true
    }
}

public struct FileTreeRow: Hashable, Sendable, Identifiable {
    public var node: FileNode
    public var depth: Int
    public var isExpanded: Bool
    public var id: URL { node.url }
}

@MainActor
@Observable
public final class FileTree {
    public let root: URL
    public var filter: FileTreeFilter
    public private(set) var expanded: Set<URL> = []
    public private(set) var listings: [URL: [FileNode]] = [:]
    public var gitBadges: GitBadgeIndex?

    public init(root: URL, filter: FileTreeFilter = .default) {
        self.root = root.standardizedFileURL
        self.filter = filter
    }

    public var rootNodes: [FileNode] { listings[root] ?? [] }

    public func children(of directory: URL) -> [FileNode]? {
        listings[directory.standardizedFileURL]
    }

    public func isExpanded(_ directory: URL) -> Bool {
        expanded.contains(directory.standardizedFileURL)
    }

    public func expand(_ directory: URL) throws {
        let key = directory.standardizedFileURL
        if listings[key] == nil { listings[key] = try Self.list(key, filter: filter) }
        expanded.insert(key)
    }

    public func collapse(_ directory: URL) {
        expanded.remove(directory.standardizedFileURL)
    }

    public func toggle(_ directory: URL) throws {
        if isExpanded(directory) { collapse(directory) } else { try expand(directory) }
    }

    public func reload() throws {
        var fresh: [URL: [FileNode]] = [root: try Self.list(root, filter: filter)]
        var keep: Set<URL> = []
        for directory in expanded {
            guard let nodes = try? Self.list(directory, filter: filter) else { continue }
            fresh[directory] = nodes
            keep.insert(directory)
        }
        listings = fresh
        expanded = keep
    }

    public func visibleRows() -> [FileTreeRow] {
        var rows: [FileTreeRow] = []
        func walk(_ directory: URL, depth: Int) {
            for node in listings[directory] ?? [] {
                let open = node.isDirectory && expanded.contains(node.url)
                rows.append(FileTreeRow(node: node, depth: depth, isExpanded: open))
                if open { walk(node.url, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return rows
    }

    public func badge(for node: FileNode) -> GitBadge? {
        gitBadges?.badge(for: node.url, isDirectory: node.isDirectory)
    }

    public func follow(_ changes: AsyncStream<Void>) async {
        for await _ in changes {
            try? reload()
        }
    }

    public nonisolated static func list(_ directory: URL, filter: FileTreeFilter = .default) throws -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [])
        let nodes = urls.compactMap { url -> FileNode? in
            let name = url.lastPathComponent
            guard filter.includes(name) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            return FileNode(
                url: url.standardizedFileURL, name: name, isDirectory: isDirectory,
                size: isDirectory ? nil : values?.fileSize
            )
        }
        return sort(nodes)
    }

    public nonisolated static func sort(_ nodes: [FileNode]) -> [FileNode] {
        nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let left = a.name.lowercased(), right = b.name.lowercased()
            return left == right ? a.name < b.name : left < right
        }
    }
}

public typealias FileTreeWatcher = GitWatcher
