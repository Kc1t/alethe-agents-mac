import Foundation

public struct GraphSnapshot: Hashable, Sendable, Identifiable {
    public var id: String
    public var url: URL
    public var createdAt: Date
    public var sizeBytes: Int

    public var createdMilliseconds: Int64 { Int64(id) ?? 0 }
}

public struct GraphifyRepository: Sendable {
    public let root: URL
    private let now: @Sendable () -> Date

    public init(root: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root.standardizedFileURL
        self.now = now
    }

    public static let outputFolder = "graphify-out"
    public static let graphFile = "graph.json"

    public var graphURL: URL { root.appending(path: Self.outputFolder).appending(path: Self.graphFile) }
    public var snapshotsFolder: URL { root.appending(path: ".alethe").appending(path: "graph-snapshots") }
    public var hasGraph: Bool { FileManager.default.fileExists(atPath: graphURL.path) }

    public static func repositoryRoot(containing directory: URL) -> URL? {
        var components = directory.standardizedFileURL.pathComponents
        while !components.isEmpty {
            let current = URL(filePath: NSString.path(withComponents: components), directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: current.appending(path: ".git").path) { return current }
            components.removeLast()
        }
        return nil
    }

    public func readGraph(limit: Int = GraphData.visualizationLimit) throws -> GraphData {
        try GraphData.parse(graphData(), limit: limit)
    }

    @discardableResult
    public func snapshot() throws -> GraphSnapshot {
        let data = try graphData()
        let manager = FileManager.default
        try manager.createDirectory(at: snapshotsFolder, withIntermediateDirectories: true)
        var milliseconds = Int64((now().timeIntervalSince1970 * 1000).rounded())
        while manager.fileExists(atPath: snapshotURL(String(milliseconds)).path) { milliseconds += 1 }
        let url = snapshotURL(String(milliseconds))
        try data.write(to: url, options: .atomic)
        return GraphSnapshot(id: String(milliseconds), url: url,
                             createdAt: Date(timeIntervalSince1970: Double(milliseconds) / 1000), sizeBytes: data.count)
    }

    public func snapshots() -> [GraphSnapshot] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: snapshotsFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.compactMap { url -> GraphSnapshot? in
            let stem = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "json", Self.isSnapshotID(stem), let milliseconds = Int64(stem) else { return nil }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return GraphSnapshot(id: stem, url: url, createdAt: Date(timeIntervalSince1970: Double(milliseconds) / 1000),
                                 sizeBytes: size)
        }
        .sorted { $0.createdMilliseconds > $1.createdMilliseconds }
    }

    public func diff(base: String, compare: String? = nil) throws -> GraphDiff {
        let baseSets = try GraphIDSets.parse(Data(contentsOf: snapshotFile(base)))
        let compareData = try compare.map { try Data(contentsOf: snapshotFile($0)) } ?? graphData()
        return GraphDiff(base: baseSets, compare: try GraphIDSets.parse(compareData))
    }

    public func rollback(to id: String) throws {
        let data = try Data(contentsOf: snapshotFile(id))
        try FileManager.default.createDirectory(at: graphURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: graphURL, options: .atomic)
    }

    @discardableResult
    public func prune(keepLast: Int, maxAgeDays: Int? = nil) -> Int {
        let nowMilliseconds = Int64((now().timeIntervalSince1970 * 1000).rounded())
        let maxAge = maxAgeDays.map { Int64($0) * 24 * 60 * 60 * 1000 }
        var removed = 0
        for (index, snapshot) in snapshots().enumerated() {
            let tooMany = index >= keepLast
            let tooOld = maxAge.map { nowMilliseconds - snapshot.createdMilliseconds > $0 } ?? false
            guard tooMany || tooOld else { continue }
            if (try? FileManager.default.removeItem(at: snapshot.url)) != nil { removed += 1 }
        }
        return removed
    }

    private func graphData() throws -> Data {
        do {
            return try Data(contentsOf: graphURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw GraphifyError.graphNotFound
        }
    }

    private func snapshotURL(_ id: String) -> URL { snapshotsFolder.appending(path: "\(id).json") }

    static func isSnapshotID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private func snapshotFile(_ id: String) throws -> URL {
        guard Self.isSnapshotID(id) else { throw GraphifyError.invalidSnapshotID }
        let url = snapshotURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw GraphifyError.snapshotNotFound }
        return url
    }
}
