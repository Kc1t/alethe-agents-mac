#if DEBUG
import Foundation

public enum DebugSampleProject {
    public static func writeFiles(in folder: URL, documents: [String: String]) throws {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, source) in documents {
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { continue }
            let target = folder.appending(path: name)
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !files.fileExists(atPath: target.path) { try source.write(to: target, atomically: true, encoding: .utf8) }
        }
    }

    @discardableResult
    public static func open(in document: inout WorkspaceDocument, folder: URL, name: String, webInterface: Bool = false) -> ProjectID {
        let id = document.projects.first { $0.folder == folder.path }?.id
            ?? document.addProject(name: name, folder: folder.path, color: .blue)
        if webInterface {
            document.openWebProject(id)
        } else {
            document.workspace.isolatedPaneID = nil
            document.workspace.fullscreenProjectID = nil
            document.open(id)
        }
        let readme = folder.appending(path: "README.md").path
        let pane = document.project(id)?.panes.first { $0.content == .markdown(path: readme) }
        if let pane {
            document.updateProject(id) { $0.activeGridID = pane.gridID }
            document.workspace.focusedPaneID = pane.id
        } else {
            document.addPane(to: id, content: .markdown(path: readme))
        }
        if webInterface { document.syncActiveTab() }
        return id
    }
}
#endif
