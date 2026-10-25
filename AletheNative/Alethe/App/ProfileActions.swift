import AletheModel
import Foundation

extension AppEnvironment {
    static var defaultProfileName: String { String(localized: "profiles.defaultName") }

    func profileName(_ entry: ProfileEntry) -> String {
        profiles?.document.displayName(of: entry, defaultName: Self.defaultProfileName) ?? Self.defaultProfileName
    }

    var activeProfileName: String {
        guard let profileID, let entry = profiles?.document.profile(profileID) else { return Self.defaultProfileName }
        return profileName(entry)
    }

    var webDisplayName: String {
        if let name = preferences?.document.displayName, !name.isEmpty { return name }
        return activeProfileName
    }

    @discardableResult
    func createProfile(named name: String) async throws -> ProfileID {
        let id = try changeProfiles { try $0.createProfile(named: name, defaultName: Self.defaultProfileName) }
        if let locations {
            try? FileManager.default.createDirectory(at: locations.profileDirectory(id), withIntermediateDirectories: true)
        }
        await profiles?.flush()
        return id
    }

    func renameProfile(_ id: ProfileID, to name: String) async throws {
        try changeProfiles { try $0.renameProfile(id, to: name, defaultName: Self.defaultProfileName) }
        await profiles?.flush()
    }

    @discardableResult
    func duplicateProfile(_ id: ProfileID) async throws -> ProfileID {
        guard let locations, let index = profiles?.document else { throw ProfileError.notFound }
        let name = index.duplicateName(for: id, format: String(localized: "profiles.copyName"),
                                       defaultName: Self.defaultProfileName)
        if id == profileID { await saveDocuments() }
        let copy = try changeProfiles { try $0.createProfile(named: name, defaultName: Self.defaultProfileName) }
        let source = locations.profileDirectory(id), destination = locations.profileDirectory(copy)
        do {
            try await Task.detached { try ProfileFiles.copyProfileFolder(from: source, to: destination) }.value
        } catch {
            try? changeProfiles { try $0.removeProfile(copy) }
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        await profiles?.flush()
        return copy
    }

    func deleteProfile(_ id: ProfileID) async throws {
        guard let locations else { throw ProfileError.notFound }
        guard id != profileID else { throw ProfileError.activeProfile }
        var next = profiles?.document ?? .initial
        try next.removeProfile(id)
        let folder = locations.profileDirectory(id)
        try await Task.detached { try ProfileFiles.trashProfileFolder(folder) }.value
        profiles?.update { $0 = next }
        await profiles?.flush()
    }

    func switchProfile(to id: ProfileID) async throws {
        guard id != profileID else { return }
        try changeProfiles { try $0.activate(id) }
        await profiles?.flush()
        relaunch()
    }

    func relaunch() {
        relaunching = true
        AppRelaunch.relaunch()
    }

    func profileSummaries() async -> [ProfileID: ProfileSummary] {
        guard let locations, let ids = profiles?.document.profiles.map(\.id) else { return [:] }
        var summaries = await Task.detached {
            Dictionary(uniqueKeysWithValues: ids.map { ($0, ProfileFiles.summary(of: $0, in: locations)) })
        }.value
        if let profileID, let document = workspace?.document {
            summaries[profileID]?.projects = document.projects.count
            summaries[profileID]?.terminals = document.projects.flatMap(\.panes).reduce(0) { $0 + $1.tabs.count }
        }
        return summaries
    }

    func saveDocuments() async {
        await workspace?.flush()
        await preferences?.flush()
        await promptHistory?.flush()
        await pullRequestReviews?.flush()
        await profiles?.flush()
    }

    @discardableResult
    private func changeProfiles<T>(_ body: (inout ProfileIndexDocument) throws -> T) throws -> T {
        guard let profiles else { throw ProfileError.notFound }
        var next = profiles.document
        let result = try body(&next)
        profiles.update { $0 = next }
        return result
    }
}

extension ProfileError {
    var localizedMessage: String {
        if case .nameRequired = self { return String(localized: "profiles.error.nameRequired") }
        if case .nameExists = self { return String(localized: "profiles.error.nameExists") }
        if case .notFound = self { return String(localized: "profiles.error.notFound") }
        if case .activeProfile = self { return String(localized: "profiles.error.activeProfile") }
        return String(localized: "profiles.error.lastProfile")
    }
}

extension AppEnvironment {
    func exportProfileBackup(_ id: ProfileID, to archive: URL) async throws {
        guard let locations, let entry = profiles?.document.profile(id) else { throw ProfileError.notFound }
        if id == profileID { await saveDocuments() }
        let folder = locations.profileDirectory(id), name = profileName(entry)
        try await Task.detached { try ProfileBackup.export(folder, to: archive, profileName: name) }.value
    }
}
