import Foundation

public enum ClaudeTranscripts {
    public static func exists(sessionID: String, homeDirectory: String = NSHomeDirectory(),
                              fileManager: FileManager = .default) -> Bool {
        guard !sessionID.isEmpty, !sessionID.contains("/") else { return false }
        let projects = "\(homeDirectory)/.claude/projects"
        let folders = (try? fileManager.contentsOfDirectory(atPath: projects)) ?? []
        return folders.contains { fileManager.fileExists(atPath: "\(projects)/\($0)/\(sessionID).jsonl") }
    }
}
