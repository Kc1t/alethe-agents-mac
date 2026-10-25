import AletheFoundation
import Foundation

extension TauriImport {
    static func importScopeGrids(_ file: File, into workspace: inout WorkspaceDocument,
                                         preferences: inout PreferencesDocument, groupIDs: [String: GroupID],
                                         includePreferences: Bool) {
        var mapped: [String: String] = [:]
        for raw in file.projects {
            guard let old = raw["id"] as? String,
                  let folder = folder(of: raw, terminals: raw["terminals"] as? [[String: Any]] ?? []),
                  let project = workspace.projects.first(where: { normalizedFolder($0.folder) ==
                      normalizedFolder(folder) }) else { continue }
            mapped[old] = project.id.rawValue
        }
        func grid(_ raw: Any?) -> CustomGrid? {
            guard let raw, var result = decodeGrid(raw) else { return nil }
            result.cells = Dictionary(result.cells.compactMap { key, cell in mapped[key].map { ($0, cell) } },
                                      uniquingKeysWith: { first, _ in first })
            return result
        }
        func history(_ raw: Any?) -> [CustomGridHistoryEntry]? {
            guard let entries = raw as? [[String: Any]] else { return nil }
            return entries.compactMap { entry in
                guard let id = entry["id"] as? String, let at = entry["savedAt"] as? Double,
                      let layout = grid(entry["layout"]) else { return nil }
                return CustomGridHistoryEntry(id: id, savedAt: Date(timeIntervalSince1970: at / 1000), layout: layout)
            }
        }
        for raw in file.groups {
            guard let old = raw["id"] as? String, let id = groupIDs[old], let layout = grid(raw["gridLayout"]) else { continue }
            let recent = history(raw["gridLayoutHistory"])
            workspace.updateGroup(id) {
                $0.layoutMode = (raw["layoutMode"] as? String).flatMap(PaneLayoutMode.init(rawValue:))
                $0.gridLayout = layout
                $0.gridLayoutHistory = recent
            }
        }
        if includePreferences {
            preferences.workspaceGridLayout = grid(file.preferences["workspaceGridLayout"])
            preferences.workspaceGridLayoutHistory = history(file.preferences["workspaceGridLayoutHistory"])
        }
    }

}
