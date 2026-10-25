import Foundation
import Observation

@Observable
@MainActor
public final class MarkdownFile {
    public let path: String
    public private(set) var source = ""
    public private(set) var blocks: [MarkdownBlock] = []
    public private(set) var loadError: String?
    public private(set) var isLoaded = false
    public private(set) var isEditing = false
    public var draft = ""
    public private(set) var saveError: String?

    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var generation = 0

    public var url: URL { URL(filePath: path) }
    public var name: String { url.lastPathComponent }
    public var hasUnsavedChanges: Bool { isEditing && draft != source }

    public init(path: String, watch: Bool = true) {
        self.path = path
        reload()
        if watch { watcher = FileWatcher(path: path) { [weak self] in self?.reload() } }
    }

    public func close() {
        watcher?.stop()
        watcher = nil
    }

    public func reload() {
        generation += 1
        let generation = generation
        let url = url
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(String, [MarkdownBlock]), Error> in
                Result {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    return (text, MarkdownBlocks.parse(text, base: url.deletingLastPathComponent()))
                }
            }.value
            guard generation == self.generation else { return }
            if case .success(let (text, blocks)) = result {
                source = text
                self.blocks = blocks
                loadError = nil
                if !isEditing { draft = text }
            } else {
                guard case .failure(let error) = result else {
                    preconditionFailure("Unexpected enum case")
                }
                loadError = error.localizedDescription
            }
            isLoaded = true
        }
    }

    public func beginEditing() {
        draft = source
        saveError = nil
        isEditing = true
    }

    public func cancelEditing() {
        isEditing = false
        draft = source
        saveError = nil
    }

    @discardableResult
    public func save() -> Bool {
        do {
            try Data(draft.utf8).write(to: url, options: .atomic)
            source = draft
            blocks = MarkdownBlocks.parse(draft, base: url.deletingLastPathComponent())
            isEditing = false
            saveError = nil
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }
}
