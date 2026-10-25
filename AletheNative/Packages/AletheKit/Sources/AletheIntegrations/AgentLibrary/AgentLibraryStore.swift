import Foundation

public enum AgentLibraryError: Error, Equatable, Sendable {
    case invalidName(String)
    case conflict(String)
    case notAlethe(String)
    case file(ConfigFileError)
}

public struct AgentLibraryChange: Equatable, Sendable {
    public struct Edit: Equatable, Sendable {
        public let url: URL
        public let previous: Data?
        public let current: Data?
    }

    public var edits: [Edit] = []
    public var skipped: [String] = []

    public var isEmpty: Bool { edits.isEmpty }

    public init(edits: [Edit] = [], skipped: [String] = []) {
        self.edits = edits
        self.skipped = skipped
    }
}

public struct AgentLibraryStore: Sendable {
    public let writer: ConfigFileWriter

    public init(writer: ConfigFileWriter) {
        self.writer = writer
    }

    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\\")
            && !name.contains("..") && !name.contains("\0")
    }

    public func installed(in scope: AgentLibraryScope) -> [InstalledAgent] {
        let directory = scope.agentsDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "md" }
            .map { url in
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return InstalledAgent(name: url.deletingPathExtension().lastPathComponent, url: url,
                                      fromAlethe: AletheAgentMarker.isAletheGenerated(text))
            }
            .sorted { $0.name < $1.name }
    }

    @discardableResult
    public func install(
        _ template: AgentTemplate, in scope: AgentLibraryScope, overwriteForeign: Bool = false
    ) throws(AgentLibraryError) -> AgentLibraryChange {
        guard Self.isValidName(template.name) else { throw .invalidName(template.name) }
        let url = scope.agentsDirectory.appending(path: template.fileName)
        let snapshot = try read(url)
        if snapshot.exists, !overwriteForeign, !AletheAgentMarker.isAletheGenerated(snapshot.text) {
            throw .conflict(template.name)
        }
        guard let edit = try write(template.content, over: snapshot, slot: scope.backupSlot) else { return AgentLibraryChange() }
        return AgentLibraryChange(edits: [edit])
    }

    @discardableResult
    public func uninstall(
        _ name: String, in scope: AgentLibraryScope, force: Bool = false
    ) throws(AgentLibraryError) -> AgentLibraryChange {
        guard Self.isValidName(name) else { throw .invalidName(name) }
        let snapshot = try read(scope.agentsDirectory.appending(path: "\(name).md"))
        guard snapshot.exists else { return AgentLibraryChange() }
        if !force, !AletheAgentMarker.isAletheGenerated(snapshot.text) { throw .notAlethe(name) }
        return AgentLibraryChange(edits: [try remove(snapshot, slot: scope.backupSlot)])
    }

    public func economyEnabled(in scope: AgentLibraryScope) -> Bool {
        let directory = scope.agentsDirectory
        return EconomyAgents.files(for: scope).allSatisfy {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: directory.appending(path: $0.fileName).path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }
    }

    @discardableResult
    public func setEconomy(_ enabled: Bool, in scope: AgentLibraryScope) throws(AgentLibraryError) -> AgentLibraryChange {
        let directory = scope.agentsDirectory
        var change = AgentLibraryChange()
        if enabled {
            for file in EconomyAgents.files(for: scope) {
                let snapshot = try read(directory.appending(path: file.fileName))
                if snapshot.exists, !EconomyAgents.isOwned(snapshot.text) {
                    change.skipped.append(file.fileName)
                    continue
                }
                if let edit = try write(file.content, over: snapshot, slot: scope.backupSlot) {
                    change.edits.append(edit)
                }
            }
        }
        let removals = (enabled ? [] : EconomyAgents.files(for: scope).map(\.fileName)) + EconomyAgents.legacyFileNames
        for name in removals {
            let snapshot = try read(directory.appending(path: name))
            guard snapshot.exists else { continue }
            guard EconomyAgents.isOwned(snapshot.text) else {
                if !enabled { change.skipped.append(name) }
                continue
            }
            change.edits.append(try remove(snapshot, slot: scope.backupSlot))
        }
        return change
    }

    @discardableResult
    public func revert(_ change: AgentLibraryChange, backupSlot slot: ConfigBackupSlot?) throws(AgentLibraryError) -> AgentLibraryChange {
        var inverse = AgentLibraryChange()
        for edit in change.edits.reversed() {
            let snapshot = try read(edit.url)
            guard snapshot.contents == edit.current else { throw .file(.changedSinceRead(edit.url)) }
            if let previous = edit.previous {
                do {
                    try writer.write(previous, over: snapshot, backupSlot: slot)
                } catch {
                    throw .file(error)
                }
                inverse.edits.append(.init(url: edit.url, previous: edit.current, current: previous))
            } else {
                inverse.edits.append(try remove(snapshot, slot: slot))
            }
        }
        return inverse
    }

    private func read(_ url: URL) throws(AgentLibraryError) -> ConfigFileSnapshot {
        do {
            return try writer.read(url)
        } catch {
            throw .file(error)
        }
    }

    private func write(
        _ text: String, over snapshot: ConfigFileSnapshot, slot: ConfigBackupSlot
    ) throws(AgentLibraryError) -> AgentLibraryChange.Edit? {
        let data = Data(text.utf8)
        guard snapshot.contents != data else { return nil }
        do {
            try writer.write(data, over: snapshot, backupSlot: slot)
        } catch {
            throw .file(error)
        }
        return .init(url: snapshot.url, previous: snapshot.contents, current: data)
    }

    private func remove(_ snapshot: ConfigFileSnapshot, slot: ConfigBackupSlot?) throws(AgentLibraryError) -> AgentLibraryChange.Edit {
        do {
            try writer.remove(over: snapshot, backupSlot: slot)
        } catch {
            throw .file(error)
        }
        return .init(url: snapshot.url, previous: snapshot.contents, current: nil)
    }
}
