import AletheFoundation
import Foundation

public struct ProfileEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: ProfileID
    public var name: String?
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(id: ProfileID, name: String?, createdAt: Date = Date(), lastUsedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public enum ProfileError: Error, Equatable, Sendable {
    case nameRequired
    case nameExists
    case notFound
    case activeProfile
    case lastProfile
}

public struct ProfileIndexDocument: VersionedDocument, Hashable {
    public static let currentVersion = 1
    public static let migrations: [Int: @Sendable (inout JSONObject) throws -> Void] = [:]
    public static let defaultProfileID = ProfileID(rawValue: "default")
    public static let initial = ProfileIndexDocument(
        profiles: [ProfileEntry(id: defaultProfileID, name: nil, createdAt: Date(timeIntervalSince1970: 0))],
        activeProfileID: defaultProfileID
    )

    public var schemaVersion: Int
    public var profiles: [ProfileEntry]
    public var activeProfileID: ProfileID

    public init(schemaVersion: Int = currentVersion, profiles: [ProfileEntry], activeProfileID: ProfileID) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.activeProfileID = activeProfileID
    }

    public var activeProfile: ProfileEntry {
        profiles.first { $0.id == activeProfileID } ?? profiles.first ?? Self.initial.profiles[0]
    }

    @discardableResult
    public mutating func addProfile(named name: String) -> ProfileID {
        let entry = ProfileEntry(id: .make(), name: name)
        profiles.append(entry)
        return entry.id
    }

    public static let maxNameLength = 64

    public static func normalizedName(_ raw: String) -> String? {
        let words = raw.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
            .split(whereSeparator: { $0.isWhitespace })
        let joined = words.joined(separator: " ")
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
    }

    public func displayName(of entry: ProfileEntry, defaultName: String) -> String {
        entry.name ?? defaultName
    }

    public func isNameTaken(_ name: String, except id: ProfileID? = nil, defaultName: String) -> Bool {
        profiles.contains {
            $0.id != id && displayName(of: $0, defaultName: defaultName)
                .compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    public func profile(_ id: ProfileID) -> ProfileEntry? {
        profiles.first { $0.id == id }
    }

    @discardableResult
    public mutating func createProfile(named raw: String, defaultName: String, now: Date = Date()) throws -> ProfileID {
        guard let name = Self.normalizedName(raw) else { throw ProfileError.nameRequired }
        guard !isNameTaken(name, defaultName: defaultName) else { throw ProfileError.nameExists }
        let entry = ProfileEntry(id: .make(), name: name, createdAt: now, lastUsedAt: now)
        profiles.append(entry)
        return entry.id
    }

    public mutating func renameProfile(_ id: ProfileID, to raw: String, defaultName: String, now: Date = Date()) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.notFound }
        guard let name = Self.normalizedName(raw) else { throw ProfileError.nameRequired }
        guard !isNameTaken(name, except: id, defaultName: defaultName) else { throw ProfileError.nameExists }
        profiles[index].name = name
        profiles[index].lastUsedAt = now
    }

    public mutating func removeProfile(_ id: ProfileID) throws {
        guard profiles.contains(where: { $0.id == id }) else { throw ProfileError.notFound }
        guard id != activeProfile.id else { throw ProfileError.activeProfile }
        guard profiles.count > 1 else { throw ProfileError.lastProfile }
        profiles.removeAll { $0.id == id }
    }

    public mutating func activate(_ id: ProfileID, now: Date = Date()) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.notFound }
        activeProfileID = id
        profiles[index].lastUsedAt = now
    }

    public func duplicateName(for id: ProfileID, format: String, defaultName: String) -> String {
        let source = profile(id).map { displayName(of: $0, defaultName: defaultName) } ?? defaultName
        let base = Self.normalizedName(String(format: format, source)) ?? source
        var candidate = base, number = 2
        while isNameTaken(candidate, defaultName: defaultName) {
            candidate = Self.normalizedName("\(base) \(number)") ?? base
            number += 1
        }
        return candidate
    }

    public func ordered(defaultName: String) -> [ProfileEntry] {
        let active = activeProfile.id
        return profiles.sorted { a, b in
            if (a.id == active) != (b.id == active) { return a.id == active }
            let aUsed = a.lastUsedAt ?? a.createdAt, bUsed = b.lastUsedAt ?? b.createdAt
            if aUsed != bUsed { return aUsed > bUsed }
            return displayName(of: a, defaultName: defaultName)
                .localizedStandardCompare(displayName(of: b, defaultName: defaultName)) == .orderedAscending
        }
    }
}

public struct DataLocations: Sendable, Hashable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func application() throws -> DataLocations {
        DataLocations(root: try AppIdentity.applicationSupportDirectory())
    }

    public var profileIndex: URL { root.appending(path: "profiles.json") }
    public var logs: URL { root.appending(path: "logs", directoryHint: .isDirectory) }

    public func profileDirectory(_ id: ProfileID) -> URL {
        root.appending(path: "profiles", directoryHint: .isDirectory)
            .appending(path: Self.safeComponent(id.rawValue), directoryHint: .isDirectory)
    }

    public func workspace(_ id: ProfileID) -> URL { profileDirectory(id).appending(path: "workspace.json") }
    public func preferences(_ id: ProfileID) -> URL { profileDirectory(id).appending(path: "preferences.json") }
    public func promptHistory(_ id: ProfileID) -> URL { profileDirectory(id).appending(path: "prompt-history.json") }
    public func pullRequestReviews(_ id: ProfileID) -> URL { profileDirectory(id).appending(path: "pull-request-reviews.json") }
    public func activityStats(_ id: ProfileID) -> URL { profileDirectory(id).appending(path: "activity-stats.json") }
    public func handoffs(_ id: ProfileID) -> URL { profileDirectory(id).appending(path: "handoffs", directoryHint: .isDirectory) }

    public var safetyBackups: URL { root.appending(path: "safety-backups", directoryHint: .isDirectory) }
    public var pendingOperation: URL { root.appending(path: "pending-operation.json") }
    public var importStaging: URL { root.appending(path: "import-staging", directoryHint: .isDirectory) }
    public func browserSession(_ id: ProfileID) -> URL {
        profileDirectory(id).appending(path: "browser-session", directoryHint: .isDirectory)
    }

    public func scrollback(_ id: ProfileID) -> URL {
        profileDirectory(id).appending(path: "scrollback", directoryHint: .isDirectory)
    }

    static func safeComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let cleaned = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.isEmpty ? "_" : cleaned
    }
}
