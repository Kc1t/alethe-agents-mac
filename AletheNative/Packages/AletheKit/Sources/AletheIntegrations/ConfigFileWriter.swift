import Foundation

public struct ConfigFileSnapshot: Sendable, Equatable {
    public let url: URL
    public let contents: Data?
    public let modificationDate: Date?

    public var exists: Bool { contents != nil }
    public var text: String { contents.map { String(decoding: $0, as: UTF8.self) } ?? "" }
}

public struct ConfigBackupSlot: Hashable, Sendable {
    public let agent: String
    public let kind: String

    public init(agent: String, kind: String) {
        self.agent = Self.sanitize(agent)
        self.kind = Self.sanitize(kind)
    }

    public var name: String { "\(agent)-\(kind)" }

    private static func sanitize(_ value: String) -> String {
        let cleaned = value.lowercased().unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "a"..."z", "0"..."9", "_": Character(scalar)
            default: "_"
            }
        }
        return cleaned.isEmpty ? "_" : String(cleaned)
    }
}

public struct ConfigBackup: Hashable, Sendable, Identifiable {
    public let url: URL
    public let slot: ConfigBackupSlot
    public let createdAt: Date
    public let size: Int

    public var id: URL { url }
}

public struct ConfigWriteReport: Sendable, Equatable {
    public let url: URL
    public let backup: ConfigBackup?
}

public enum ConfigFileError: Error, Equatable, Sendable {
    case changedSinceRead(URL)
    case unreadable(URL, String)
    case backupFailed(URL, String)
    case writeFailed(URL, String)
}

public struct ConfigFileWriter: Sendable {
    public static let maxBackups = 10
    public static let backupsFolderName = "config-backups"

    public let backupRoot: URL
    private let now: @Sendable () -> Date

    public init(profileDirectory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(backupRoot: profileDirectory.appending(path: Self.backupsFolderName, directoryHint: .isDirectory), now: now)
    }

    public init(backupRoot: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backupRoot = backupRoot
        self.now = now
    }

    public func read(_ url: URL) throws(ConfigFileError) -> ConfigFileSnapshot {
        let target = Self.resolved(url)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: target.path) else {
            return ConfigFileSnapshot(url: url, contents: nil, modificationDate: nil)
        }
        do {
            let date = try fileManager.attributesOfItem(atPath: target.path)[.modificationDate] as? Date
            let data = try Data(contentsOf: target)
            return ConfigFileSnapshot(url: url, contents: data, modificationDate: date)
        } catch {
            throw .unreadable(url, error.localizedDescription)
        }
    }

    @discardableResult
    public func write(_ data: Data, over snapshot: ConfigFileSnapshot, backupSlot slot: ConfigBackupSlot?) throws(ConfigFileError) -> ConfigWriteReport {
        let current = try read(snapshot.url)
        guard current == snapshot else { throw .changedSinceRead(snapshot.url) }
        var backup: ConfigBackup?
        if let contents = current.contents, let slot {
            backup = try store(contents, of: snapshot.url, in: slot)
        }
        try Self.atomicWrite(data, to: Self.resolved(snapshot.url))
        return ConfigWriteReport(url: snapshot.url, backup: backup)
    }

    @discardableResult
    public func write(_ text: String, over snapshot: ConfigFileSnapshot, backupSlot slot: ConfigBackupSlot?) throws(ConfigFileError) -> ConfigWriteReport {
        try write(Data(text.utf8), over: snapshot, backupSlot: slot)
    }

    @discardableResult
    public func remove(over snapshot: ConfigFileSnapshot, backupSlot slot: ConfigBackupSlot?) throws(ConfigFileError) -> ConfigWriteReport {
        let current = try read(snapshot.url)
        guard current == snapshot else { throw .changedSinceRead(snapshot.url) }
        guard let contents = current.contents else { return ConfigWriteReport(url: snapshot.url, backup: nil) }
        var backup: ConfigBackup?
        if let slot {
            backup = try store(contents, of: snapshot.url, in: slot)
        }
        do {
            try FileManager.default.removeItem(at: snapshot.url)
        } catch {
            throw .writeFailed(snapshot.url, error.localizedDescription)
        }
        return ConfigWriteReport(url: snapshot.url, backup: backup)
    }

    public func backups(in slot: ConfigBackupSlot) -> [ConfigBackup] {
        let folder = folder(for: slot)
        let prefix = slot.name + "-"
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.compactMap { url -> ConfigBackup? in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix) else { return nil }
            let stamp = name.dropFirst(prefix.count).prefix { $0.isNumber }
            guard let milliseconds = Int64(stamp) else { return nil }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return ConfigBackup(
                url: url,
                slot: slot,
                createdAt: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000),
                size: size
            )
        }
        .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    @discardableResult
    public func restore(_ backup: ConfigBackup, to url: URL) throws(ConfigFileError) -> ConfigWriteReport {
        let data: Data
        do {
            data = try Data(contentsOf: backup.url)
        } catch {
            throw .unreadable(backup.url, error.localizedDescription)
        }
        return try write(data, over: read(url), backupSlot: backup.slot)
    }

    private func folder(for slot: ConfigBackupSlot) -> URL {
        backupRoot.appending(path: slot.name, directoryHint: .isDirectory)
    }

    private func store(_ contents: Data, of url: URL, in slot: ConfigBackupSlot) throws(ConfigFileError) -> ConfigBackup {
        let folder = folder(for: slot)
        let fileManager = FileManager.default
        let fileExtension = url.pathExtension.isEmpty ? "bak" : url.pathExtension
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var milliseconds = Int64((now().timeIntervalSince1970 * 1000).rounded(.down))
            var target: URL
            repeat {
                target = folder.appending(path: "\(slot.name)-\(String(format: "%015lld", milliseconds)).\(fileExtension)")
                milliseconds += 1
            } while fileManager.fileExists(atPath: target.path)
            try contents.write(to: target, options: .withoutOverwriting)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            prune(slot)
            return ConfigBackup(
                url: target,
                slot: slot,
                createdAt: Date(timeIntervalSince1970: TimeInterval(milliseconds - 1) / 1000),
                size: contents.count
            )
        } catch {
            throw .backupFailed(url, error.localizedDescription)
        }
    }

    private func prune(_ slot: ConfigBackupSlot) {
        for stale in backups(in: slot).dropFirst(Self.maxBackups) {
            try? FileManager.default.removeItem(at: stale.url)
        }
    }

    static func resolved(_ url: URL) -> URL {
        url.resolvingSymlinksInPath()
    }

    static func atomicWrite(_ data: Data, to url: URL) throws(ConfigFileError) {
        let fileManager = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).alethe-tmp-\(UUID().uuidString.prefix(8))")
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: temporary, options: .withoutOverwriting)
            if let permissions = try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] {
                try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
            }
            guard rename(temporary.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw .writeFailed(url, error.localizedDescription)
        }
    }
}
