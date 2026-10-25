import Foundation

public struct ProfileSummary: Hashable, Sendable {
    public var projects: Int
    public var terminals: Int
    public var bytes: Int64

    public init(projects: Int = 0, terminals: Int = 0, bytes: Int64 = 0) {
        self.projects = projects
        self.terminals = terminals
        self.bytes = bytes
    }
}

public enum ProfileFiles {
    public static func counts(ofWorkspaceAt url: URL) -> (projects: Int, terminals: Int) {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = object["projects"] as? [[String: Any]] else { return (0, 0) }
        let terminals = projects
            .flatMap { ($0["panes"] as? [[String: Any]]) ?? [] }
            .reduce(0) { $0 + (($1["tabs"] as? [Any])?.count ?? 0) }
        return (projects.count, terminals)
    }

    public static func summary(of id: ProfileID, in locations: DataLocations) -> ProfileSummary {
        let counts = counts(ofWorkspaceAt: locations.workspace(id))
        return ProfileSummary(projects: counts.projects, terminals: counts.terminals,
                              bytes: size(of: locations.profileDirectory(id)))
    }

    public static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    public static func isRuntimeFile(relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/")
        guard let first = components.first, let last = components.last else { return false }
        if first.caseInsensitiveCompare("EBWebView") == .orderedSame { return true }
        if last == ".DS_Store" { return true }
        let ext = (last as NSString).pathExtension.lowercased()
        return ext == "tmp" || ext == "log"
    }

    public static func copyProfileFolder(from source: URL, to destination: URL, skipping: Set<String> = []) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard manager.fileExists(atPath: source.path) else { return }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = manager.enumerator(at: source, includingPropertiesForKeys: keys) else { return }
        let base = source.resolvingSymlinksInPath().path
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { continue }
            let relative = String(url.resolvingSymlinksInPath().path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty else { continue }
            let topLevel = relative.split(separator: "/").first.map(String.init) ?? relative
            if isRuntimeFile(relativePath: relative) || skipping.contains(topLevel) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            let target = destination.appending(path: relative)
            if values.isDirectory == true {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
            } else if values.isRegularFile == true {
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: url, to: target)
            }
        }
    }

    public static func trashProfileFolder(_ directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.trashItem(at: directory, resultingItemURL: nil)
    }
}
