import AletheFoundation
import Foundation

public enum TodoTemplate {
    public static let fileName = "alethe-todo.template.jsonc"
    public static let schemaVersion = 1

    public static let defaultContent = """
    // Alethe Todo template

    // For now, the app stores Todo items in its local profile; this template documents
    // the structure expected by the importer/sync layer.
    {
      // Schema version for future migrations.
      "version": 1,

      // Global personal task list. Order in this array is the visible order.
      "todos": [
        {
          // Stable id. Any unique string is accepted.
          "id": "task-example-1",

          // Text shown in the Todo sidebar.
          "title": "Example task",

          // false = Active, true = Completed.
          "completed": false
        }
      ]
    }

    """

    public enum TemplateError: Error, Equatable {
        case emptyDirectory
        case notADirectory
        case invalidDocument(String)
    }

    @discardableResult
    public static func ensure(in directory: URL, fileManager: FileManager = .default) throws -> URL {
        guard !directory.path.trimmingCharacters(in: .whitespaces).isEmpty else { throw TemplateError.emptyDirectory }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TemplateError.notADirectory
        }
        let url = directory.appending(path: fileName)
        if !fileManager.fileExists(atPath: url.path) {
            try Data(defaultContent.utf8).write(to: url, options: .atomic)
        }
        return url
    }

    @discardableResult
    public static func ensure(in directory: URL, using files: TodoFileAccess) async throws -> URL {
        guard !directory.path.trimmingCharacters(in: .whitespaces).isEmpty else { throw TemplateError.emptyDirectory }
        let url = directory.appending(path: fileName)
        do {
            _ = try await files.read(url)
        } catch where TodoFileAccess.isMissingFile(error) {
            try await files.write(Data(defaultContent.utf8), url)
        }
        return url
    }

    struct Entry: Codable {
        var id: String?
        var title: String
        var completed: Bool?
        var tags: [String]?
        var projectId: String?
        var prUrl: String?
    }

    struct Document: Codable {
        var version: Int?
        var todos: [Entry]
    }

    public static func parse(_ data: Data, now: Date = Date()) throws -> [Todo] {
        let json = JSONC.strip(String(decoding: data, as: UTF8.self))
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        } catch {
            throw TemplateError.invalidDocument(String(describing: error))
        }
        var seen = Set<String>()
        var todos: [Todo] = []
        for entry in document.todos {
            let title = TodoRules.normalizeTitle(entry.title)
            guard !title.isEmpty else { continue }
            var id = entry.id?.trimmingCharacters(in: .whitespaces) ?? ""
            if id.isEmpty || seen.contains(id) { id = UUID().uuidString }
            seen.insert(id)
            todos.append(Todo(
                id: id,
                title: title,
                done: entry.completed ?? false,
                tags: TodoRules.normalizeTags(entry.tags ?? []),
                prURL: entry.prUrl.flatMap(URL.init(string:)),
                projectID: entry.projectId,
                order: todos.count,
                createdAt: now
            ))
        }
        return todos
    }

    public static func render(_ todos: [Todo]) throws -> Data {
        let document = Document(version: schemaVersion, todos: todos.map {
            Entry(
                id: $0.id,
                title: $0.title,
                completed: $0.done,
                tags: $0.tags.isEmpty ? nil : $0.tags,
                projectId: $0.projectID,
                prUrl: $0.prURL?.absoluteString
            )
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let body = String(decoding: try encoder.encode(document), as: UTF8.self)
        return Data("// Alethe Todo list. Order in \"todos\" is the visible order.\n\(body)\n".utf8)
    }
}

public struct TodoFileAccess: Sendable {
    public var read: @Sendable (URL) async throws -> Data
    public var write: @Sendable (Data, URL) async throws -> Void

    public init(read: @escaping @Sendable (URL) async throws -> Data, write: @escaping @Sendable (Data, URL) async throws -> Void) {
        self.read = read
        self.write = write
    }

    public static func isMissingFile(_ error: any Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .fileReadNoSuchFile || cocoa.code == .fileNoSuchFile { return true }
        if let posix = error as? POSIXError, posix.code == .ENOENT { return true }
        let ns = error as NSError
        return ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT)
    }
}
