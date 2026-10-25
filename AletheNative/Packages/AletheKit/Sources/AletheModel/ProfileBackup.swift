import Foundation

public enum BackupError: Error, Equatable, Sendable {
    case targetInsideSource
    case unreadableArchive
    case unsafeEntry(String)
    case notAProfileBackup
    case tauriBackup
    case newerFormat
    case archiveFailed(String)
}

public struct BackupManifest: Codable, Hashable, Sendable {
    public static let fileName = "alethe-backup.json"
    public static let currentFormat = 1

    public var format: Int
    public var createdAt: Date
    public var profileName: String?

    public init(format: Int = currentFormat, createdAt: Date, profileName: String?) {
        self.format = format
        self.createdAt = createdAt
        self.profileName = profileName
    }
}

public struct BackupContents: Hashable, Sendable {
    public var manifest: BackupManifest?
    public var projects: Int
    public var terminals: Int
    public var files: Int
    public var bytes: Int64
    public var hasScrollback: Bool
}

public struct StagedBackup: Hashable, Sendable {
    public var folder: URL
    public var contents: BackupContents
}

public enum ProfileBackup {
    public static let keptSafetyBackups = 10

    public static func export(_ directory: URL, to archive: URL, profileName: String?, skipping: Set<String> = [],
                              now: Date = Date()) throws {
        let source = directory.resolvingSymlinksInPath().path
        let parent = archive.deletingLastPathComponent().resolvingSymlinksInPath().path
        if parent == source || parent.hasPrefix(source + "/") {
            let topLevel = String(parent.dropFirst(source.count)).split(separator: "/").first.map(String.init)
            guard let topLevel, skipping.contains(topLevel) else { throw BackupError.targetInsideSource }
        }
        let manager = FileManager.default
        let work = manager.temporaryDirectory.appending(path: "alethe-backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: work) }
        let staging = work.appending(path: "profile", directoryHint: .isDirectory)
        try ProfileFiles.copyProfileFolder(from: directory, to: staging, skipping: skipping)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(BackupManifest(createdAt: now, profileName: profileName))
            .write(to: staging.appending(path: BackupManifest.fileName))
        let written = work.appending(path: "backup.zip")
        try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", staging.path, written.path])
        try manager.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: archive.path) { _ = try manager.replaceItemAt(archive, withItemAt: written) } else {
            try manager.moveItem(at: written, to: archive)
        }
    }

    public static func entries(of archive: URL) throws -> [String] {
        let output: String
        do {
            output = try run("/usr/bin/unzip", ["-Z1", archive.path], mergingErrors: false)
        } catch {
            throw BackupError.unreadableArchive
        }
        return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    public static func isUnsafe(entry: String) -> Bool {
        let name = entry.replacingOccurrences(of: "\\", with: "/")
        return name.hasPrefix("/") || name.hasPrefix("~") || name.split(separator: "/").contains("..")
    }

    public static func stage(_ archive: URL, into staging: URL) throws -> StagedBackup {
        let manager = FileManager.default
        let names = try entries(of: archive)
        if let unsafe = names.first(where: isUnsafe) { throw BackupError.unsafeEntry(unsafe) }
        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            do {
                try run("/usr/bin/ditto", ["-x", "-k", "--norsrc", "--noqtn", archive.path, staging.path])
            } catch {
                throw BackupError.unreadableArchive
            }
            try? manager.removeItem(at: staging.appending(path: "__MACOSX"))
            let root = try profileRoot(in: staging)
            if root != staging { try hoist(root, into: staging) }
            try removeRuntimeFilesAndRefuseLinks(in: staging)
            let contents = try validate(staging)
            try? manager.removeItem(at: staging.appending(path: BackupManifest.fileName))
            return StagedBackup(folder: staging, contents: contents)
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    private static func profileRoot(in staging: URL) throws -> URL {
        let manager = FileManager.default
        if manager.fileExists(atPath: staging.appending(path: "workspace.json").path) { return staging }
        let children = try manager.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles])
        if children.count == 1, let only = children.first,
           (try? only.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
           manager.fileExists(atPath: only.appending(path: "workspace.json").path)
            || manager.fileExists(atPath: only.appending(path: "projects.json").path) {
            return only
        }
        return staging
    }

    private static func hoist(_ folder: URL, into staging: URL) throws {
        let manager = FileManager.default
        let moved = staging.deletingLastPathComponent().appending(path: "\(staging.lastPathComponent)-\(UUID().uuidString)")
        try manager.moveItem(at: folder, to: moved)
        try manager.removeItem(at: staging)
        try manager.moveItem(at: moved, to: staging)
    }

    private static func removeRuntimeFilesAndRefuseLinks(in staging: URL) throws {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]
        guard let enumerator = manager.enumerator(at: staging, includingPropertiesForKeys: keys) else { return }
        let base = staging.resolvingSymlinksInPath().path
        var runtime: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            let relative = String(url.deletingLastPathComponent().resolvingSymlinksInPath()
                .appending(path: url.lastPathComponent).path.dropFirst(base.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if values.isSymbolicLink == true { throw BackupError.unsafeEntry(relative) }
            if ProfileFiles.isRuntimeFile(relativePath: relative) {
                runtime.append(url)
                if values.isDirectory == true { enumerator.skipDescendants() }
            } else if values.isDirectory != true, values.isRegularFile != true {
                throw BackupError.unsafeEntry(relative)
            }
        }
        for url in runtime { try? manager.removeItem(at: url) }
    }

    private static func validate(_ staging: URL) throws -> BackupContents {
        let manager = FileManager.default
        let workspace = staging.appending(path: "workspace.json")
        guard manager.fileExists(atPath: workspace.path) else {
            if manager.fileExists(atPath: staging.appending(path: "projects.json").path) { throw BackupError.tauriBackup }
            throw BackupError.notAProfileBackup
        }
        guard let data = try? Data(contentsOf: workspace),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["projects"] is [Any] else { throw BackupError.notAProfileBackup }
        if let version = object["schemaVersion"] as? Int, version > WorkspaceDocument.currentVersion { throw BackupError.newerFormat }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = (try? Data(contentsOf: staging.appending(path: BackupManifest.fileName)))
            .flatMap { try? decoder.decode(BackupManifest.self, from: $0) }
        if let manifest, manifest.format > BackupManifest.currentFormat { throw BackupError.newerFormat }
        let counts = ProfileFiles.counts(ofWorkspaceAt: workspace)
        var files = 0
        if let enumerator = manager.enumerator(at: staging, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in enumerator
            where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && url.lastPathComponent != BackupManifest.fileName {
                files += 1
            }
        }
        let scrollback = staging.appending(path: "scrollback")
        let hasScrollback = ((try? manager.contentsOfDirectory(atPath: scrollback.path)) ?? []).contains { $0.hasSuffix(".bin") }
        return BackupContents(manifest: manifest, projects: counts.projects, terminals: counts.terminals,
                              files: files, bytes: ProfileFiles.size(of: staging), hasScrollback: hasScrollback)
    }

    @discardableResult
    public static func safetyBackup(of directory: URL, label: String, into folder: URL, profileName: String?,
                                    skipping: Set<String> = [], now: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let archive = folder.appending(path: "\(label)-\(formatter.string(from: now)).zip")
        try export(directory, to: archive, profileName: profileName, skipping: skipping, now: now)
        prune(folder, label: label, keeping: keptSafetyBackups)
        return archive
    }

    public static func prune(_ folder: URL, label: String, keeping count: Int) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix("\(label)-") && $0.hasSuffix(".zip") }
            .sorted(by: >)
        for name in names.dropFirst(count) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String], mergingErrors: Bool = true) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = mergingErrors ? pipe : FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw BackupError.archiveFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}

public enum PendingDataOperation: Codable, Hashable, Sendable {
    case importProfile(ProfileID, stagedFolder: String)
    case resetProfile(ProfileID)
    case eraseAll
}

public enum DataMaintenance {
    public static func maintenanceEntries(_ locations: DataLocations) -> Set<String> {
        [locations.safetyBackups.lastPathComponent, locations.importStaging.lastPathComponent,
         locations.pendingOperation.lastPathComponent]
    }

    public static func schedule(_ operation: PendingDataOperation, in locations: DataLocations) throws {
        try FileManager.default.createDirectory(at: locations.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(operation).write(to: locations.pendingOperation, options: .atomic)
    }

    public static func cancelPending(in locations: DataLocations) {
        try? FileManager.default.removeItem(at: locations.pendingOperation)
        try? FileManager.default.removeItem(at: locations.importStaging)
    }

    public static func pending(in locations: DataLocations) -> PendingDataOperation? {
        guard let data = try? Data(contentsOf: locations.pendingOperation) else { return nil }
        return try? JSONDecoder().decode(PendingDataOperation.self, from: data)
    }

    @discardableResult
    public static func applyPending(in locations: DataLocations) throws -> PendingDataOperation? {
        let manager = FileManager.default
        let operation = pending(in: locations)
        try? manager.removeItem(at: locations.pendingOperation)
        defer { try? manager.removeItem(at: locations.importStaging) }
        guard let operation else { return nil }
        if case .importProfile(let id, let path) = operation {
            let staged = URL(filePath: path, directoryHint: .isDirectory)
            let staging = locations.importStaging.resolvingSymlinksInPath().path
            guard staged.resolvingSymlinksInPath().path.hasPrefix(staging + "/"),
                  manager.fileExists(atPath: staged.path) else { throw BackupError.notAProfileBackup }
            let target = locations.profileDirectory(id)
            let previous = locations.importStaging.appending(path: "previous-\(UUID().uuidString)")
            let hadTarget = manager.fileExists(atPath: target.path)
            if hadTarget { try manager.moveItem(at: target, to: previous) }
            do {
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.moveItem(at: staged, to: target)
            } catch {
                if hadTarget { try? manager.moveItem(at: previous, to: target) }
                throw error
            }
        } else if case .resetProfile(let id) = operation {
            let target = locations.profileDirectory(id)
            if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
        } else {
            let keep = maintenanceEntries(locations)
            for name in (try? manager.contentsOfDirectory(atPath: locations.root.path)) ?? [] where !keep.contains(name) {
                try manager.removeItem(at: locations.root.appending(path: name))
            }
        }
        return operation
    }
}
