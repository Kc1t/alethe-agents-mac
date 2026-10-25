import AletheFoundation
import Foundation

extension TauriImport {
    static func importGroups(_ file: File, into workspace: inout WorkspaceDocument,
                                     report: inout Report) -> [String: GroupID] {
        let groups = file.groups.filter { $0["archived"] as? Bool != true }
        let known = Set(groups.compactMap { $0["id"] as? String })
        var mapped: [String: GroupID] = [:]
        var pending = groups
        while !pending.isEmpty {
            let before = pending.count
            pending.removeAll { group in
                guard let id = group["id"] as? String else { return true }
                let parent = (group["parentGroupId"] as? String).flatMap { known.contains($0) ? $0 : nil }
                if let parent, mapped[parent] == nil { return false }
                let parentID = parent.flatMap { mapped[$0] }
                let name = (group["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Group"
                if let existing = workspace.childGroups(of: parentID).first(where: { $0.name == name }) {
                    mapped[id] = existing.id
                } else {
                    let created = workspace.addGroup(name: name, color: projectColor(group["color"]), parent: parentID)
                    workspace.updateGroup(created) {
                        $0.isCollapsed = group["collapsed"] as? Bool ?? false
                        $0.iconUrl = group["iconUrl"] as? String
                    }
                    mapped[id] = created
                    report.groups += 1
                }
                return true
            }
            if pending.count == before {
                pending = pending.map { var group = $0; group["parentGroupId"] = nil; return group }
            }
        }
        return mapped
    }

}
