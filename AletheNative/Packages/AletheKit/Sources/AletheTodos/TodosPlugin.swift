import AlethePluginKit
import Foundation

@MainActor
public final class TodosPlugin: AlethePlugin {
    public static let manifest = PluginManifest(
        id: "com.alethe.todos",
        version: "1.0.0",
        name: "Todo List",
        capabilities: [.storage, .filesystemRead, .filesystemWrite]
    )

    public static let viewID = "todos"
    public static let sidebarTabID = "todos"
    public static let newTodoCommandID = "todos.new"

    public static var activeStore: TodoStore? { activePlugin?.store }
    public private(set) static var activePlugin: TodosPlugin?
    public static var onNewTodo: (@MainActor () -> Void)?

    public private(set) var store: TodoStore?
    private var context: PluginContext?

    public init() {}

    public func activate(context: PluginContext) throws {
        let store = TodoStore(storage: try context.storage())
        try context.addSidebarTab(SidebarTabContribution(
            id: Self.sidebarTabID,
            title: "Todo",
            symbol: "checklist",
            side: .right,
            viewID: Self.viewID
        ))
        try context.addCommand(CommandContribution(
            id: Self.newTodoCommandID,
            title: "New Todo"
        ) {
            TodosPlugin.onNewTodo?()
        })
        self.store = store
        self.context = context
        Self.activePlugin = self
        Task { await store.load() }
    }

    public func deactivate() {
        if Self.activePlugin === self { Self.activePlugin = nil }
        store = nil
        context = nil
    }

    public enum TemplateAccessError: Error, Equatable {
        case inactive
    }

    public var fileAccess: TodoFileAccess? {
        guard let context else { return nil }
        return TodoFileAccess(
            read: { url in try await context.readFile(at: url) },
            write: { data, url in try await context.writeFile(data, to: url) }
        )
    }

    public func ensureTemplate() async throws -> URL {
        guard let store, let fileAccess else { throw TemplateAccessError.inactive }
        return try await store.ensureTemplate(using: fileAccess)
    }

    public func importTemplate() async throws {
        guard let store, let fileAccess else { throw TemplateAccessError.inactive }
        let url = try await store.ensureTemplate(using: fileAccess)
        try await store.importTemplate(from: url, using: fileAccess)
    }

    public func exportTemplate() async throws -> URL {
        guard let store, let fileAccess else { throw TemplateAccessError.inactive }
        guard let url = store.templateURL else { throw TodoTemplate.TemplateError.emptyDirectory }
        try await store.exportTemplate(to: url, using: fileAccess)
        return url
    }
}
