import Foundation

public struct TauriProfile: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var projectsFile: URL
    public var isActive: Bool

    public init(id: String, name: String, projectsFile: URL, isActive: Bool) {
        self.id = id
        self.name = name
        self.projectsFile = projectsFile
        self.isActive = isActive
    }
}

public enum TauriDataLocation {
    public static func defaultRoot(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "com.kc1t.alethe", directoryHint: .isDirectory)
    }

    public static func profiles(root: URL, fileManager: FileManager = .default) -> [TauriProfile] {
        var entries: [(id: String, name: String?)] = []
        var active: String?
        if let data = try? Data(contentsOf: root.appending(path: "profiles.json")),
           let index = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            active = index["active_profile_id"] as? String
            for profile in index["profiles"] as? [[String: Any]] ?? [] {
                if let id = profile["id"] as? String { entries.append((id, profile["name"] as? String)) }
            }
        }
        let folders = (try? fileManager.contentsOfDirectory(atPath: root.appending(path: "profiles").path)) ?? []
        for folder in folders.sorted() where !entries.contains(where: { $0.id == folder }) {
            entries.append((folder, nil))
        }
        let found = entries.compactMap { entry -> TauriProfile? in
            guard !entry.id.contains("/"), !entry.id.hasPrefix(".") else { return nil }
            let file = root.appending(path: "profiles").appending(path: entry.id).appending(path: "projects.json")
            guard fileManager.fileExists(atPath: file.path) else { return nil }
            let name = entry.name.flatMap { $0.isEmpty ? nil : $0 } ?? entry.id
            return TauriProfile(id: entry.id, name: name, projectsFile: file, isActive: entry.id == (active ?? "default"))
        }
        return found.filter(\.isActive) + found.filter { !$0.isActive }
    }
}
