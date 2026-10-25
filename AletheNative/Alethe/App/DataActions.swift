import AletheIntegrations
import AletheModel
import AppKit
import Foundation

extension AppEnvironment {
    func exportBackup(to archive: URL) async throws {
        guard let locations, let profileID else { throw ProfileError.notFound }
        await saveDocuments()
        let folder = locations.profileDirectory(profileID), name = activeProfileName
        try await Task.detached { try ProfileBackup.export(folder, to: archive, profileName: name) }.value
    }

    func stageBackup(_ archive: URL) async throws -> StagedBackup {
        guard let locations else { throw ProfileError.notFound }
        let staging = locations.importStaging.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return try await Task.detached { try ProfileBackup.stage(archive, into: staging) }.value
    }

    func discardStaged(_ staged: StagedBackup) {
        let folder = staged.folder
        Task.detached { try? FileManager.default.removeItem(at: folder) }
    }

    func importStaged(_ staged: StagedBackup) async throws {
        guard let profileID else { throw ProfileError.notFound }
        try await scheduleAfterSafetyBackup(.importProfile(profileID, stagedFolder: staged.folder.path))
    }

    func importGistPull(_ pull: StagedGistPull) async throws {
        guard let profileID, case .importProfile(profileID, _) = pull.operation else { throw ProfileError.notFound }
        try await scheduleAfterSafetyBackup(pull.operation)
    }

    func resetProfileData() async throws {
        guard let profileID else { throw ProfileError.notFound }
        try await scheduleAfterSafetyBackup(.resetProfile(profileID))
    }

    func eraseAllData() async throws {
        try await scheduleAfterSafetyBackup(.eraseAll)
    }

    func openDataFolder() {
        guard let locations else { return }
        try? FileManager.default.createDirectory(at: locations.root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(locations.root)
    }

    func revealSafetyBackups() {
        guard let locations else { return }
        try? FileManager.default.createDirectory(at: locations.safetyBackups, withIntermediateDirectories: true)
        NSWorkspace.shared.open(locations.safetyBackups)
    }

    private func scheduleAfterSafetyBackup(_ operation: PendingDataOperation) async throws {
        guard let locations, let profileID else { throw ProfileError.notFound }
        await saveDocuments()
        let name = activeProfileName
        try await Task.detached {
            if case .eraseAll = operation {
                try ProfileBackup.safetyBackup(of: locations.root, label: "all-data", into: locations.safetyBackups,
                                               profileName: nil, skipping: DataMaintenance.maintenanceEntries(locations))
            } else {
                try ProfileBackup.safetyBackup(of: locations.profileDirectory(profileID), label: "profile-\(profileID.rawValue)",
                                               into: locations.safetyBackups, profileName: name)
            }
            try DataMaintenance.schedule(operation, in: locations)
        }.value
        relaunch()
    }
}

extension BackupError {
    var localizedMessage: String {
        if case .targetInsideSource = self { return String(localized: "settings.data.error.insideProfile") }
        if case .unreadableArchive = self { return String(localized: "settings.data.error.unreadable") }
        if case .unsafeEntry(let name) = self { return String(format: String(localized: "settings.data.error.unsafe"), name) }
        if case .notAProfileBackup = self { return String(localized: "settings.data.error.notBackup") }
        if case .tauriBackup = self { return String(localized: "settings.data.error.tauri") }
        if case .newerFormat = self { return String(localized: "settings.data.error.newer") }
        if case .archiveFailed(let message) = self { return String(format: String(localized: "settings.data.error.archive"), message) }
        preconditionFailure("Unreachable case")
    }
}
