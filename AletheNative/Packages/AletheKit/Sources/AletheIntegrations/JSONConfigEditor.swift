import AletheFoundation
import Foundation

public enum JSONConfigError: Error, Equatable, Sendable {
    case unparsable(OrderedJSONParseError)
    case rootNotAnObject
    case notAnObject(path: [String])
    case emptyPath
}

public struct JSONConfigEditor: Sendable, Equatable {
    public private(set) var root: OrderedJSONObject

    public init(root: OrderedJSONObject = OrderedJSONObject()) {
        self.root = root
    }

    public init(parsing text: String, allowComments: Bool = false) throws(JSONConfigError) {
        let source = allowComments ? JSONC.strip(text) : text
        guard !source.allSatisfy(\.isWhitespace) else {
            self.init()
            return
        }
        let value: OrderedJSON
        do {
            value = try OrderedJSON.parse(source)
        } catch {
            throw .unparsable(error)
        }
        guard case .object(let object) = value else { throw .rootNotAnObject }
        self.init(root: object)
    }

    public init(parsing data: Data, allowComments: Bool = false) throws(JSONConfigError) {
        try self.init(parsing: String(decoding: data, as: UTF8.self), allowComments: allowComments)
    }

    public func value(at path: [String]) -> OrderedJSON? {
        guard let last = path.last else { return .object(root) }
        var object = root
        for key in path.dropLast() {
            guard let next = object[key]?.objectValue else { return nil }
            object = next
        }
        return object[last]
    }

    public mutating func set(_ value: OrderedJSON, at path: [String]) throws(JSONConfigError) {
        guard !path.isEmpty else { throw .emptyPath }
        try Self.update(&root, path: path[...], fullPath: path, create: true) { object, key in
            object[key] = value
        }
    }

    @discardableResult
    public mutating func remove(at path: [String]) throws(JSONConfigError) -> OrderedJSON? {
        guard !path.isEmpty else { throw .emptyPath }
        var removed: OrderedJSON?
        try Self.update(&root, path: path[...], fullPath: path, create: false) { object, key in
            removed = object.removeValue(forKey: key)
        }
        return removed
    }

    public mutating func upsertObject(
        at path: [String],
        managedKeys: [String],
        values: [(String, OrderedJSON)]
    ) throws(JSONConfigError) {
        guard !path.isEmpty else { throw .emptyPath }
        var entry: OrderedJSONObject
        let existingValue = value(at: path)
        if case .none = existingValue {
            entry = OrderedJSONObject()
        } else if case .object(let existing) = existingValue {
            entry = existing
        } else {
            throw .notAnObject(path: path)
        }
        for key in managedKeys { entry.removeValue(forKey: key) }
        for (key, value) in values { entry[key] = value }
        try set(.object(entry), at: path)
    }

    public func rendered() -> String {
        OrderedJSON.object(root).rendered() + "\n"
    }

    public func renderedData() -> Data {
        Data(rendered().utf8)
    }

    private static func update(
        _ object: inout OrderedJSONObject,
        path: ArraySlice<String>,
        fullPath: [String],
        create: Bool,
        _ body: (inout OrderedJSONObject, String) -> Void
    ) throws(JSONConfigError) {
        let key = path[path.startIndex]
        if path.count == 1 {
            body(&object, key)
            return
        }
        var child: OrderedJSONObject
        if case .none = object[key] {
            guard create else { return }
            child = OrderedJSONObject()
        } else if case .object(let existing) = object[key] {
            child = existing
        } else {
            throw .notAnObject(path: Array(fullPath[..<(path.startIndex + 1)]))
        }
        try update(&child, path: path.dropFirst(), fullPath: fullPath, create: create, body)
        object[key] = .object(child)
    }
}
