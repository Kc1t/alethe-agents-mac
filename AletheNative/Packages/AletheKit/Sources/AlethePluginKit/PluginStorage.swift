import AletheFoundation
import Foundation

public actor PluginStorage {
    public nonisolated let url: URL
    private let debounce: Duration
    private var values: JSONObject?
    private var dirty = false
    private var debounceTask: Task<Void, Never>?
    private(set) var writeCount = 0

    public init(url: URL, debounce: Duration = .milliseconds(300)) {
        self.url = url
        self.debounce = debounce
    }

    public init(root: URL, pluginID: String, debounce: Duration = .milliseconds(300)) {
        self.init(url: root.appending(path: "plugin-data", directoryHint: .isDirectory)
            .appending(path: "\(pluginID).json"), debounce: debounce)
    }

    public func value(forKey key: String) -> JSONValue? {
        loaded()[key]
    }

    public var allValues: JSONObject { loaded() }

    public func set(_ value: JSONValue?, forKey key: String) {
        var current = loaded()
        current[key] = value
        values = current
        dirty = true
        scheduleWrite()
    }

    public func decode<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let value = loaded()[key] else { return nil }
        return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    public func encode<T: Encodable>(_ value: T, forKey key: String) throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        set(json, forKey: key)
    }

    public func flush() throws {
        debounceTask?.cancel()
        debounceTask = nil
        try writeIfDirty()
    }

    private func scheduleWrite() {
        debounceTask?.cancel()
        debounceTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            try? self.writeIfDirty()
        }
    }

    private func loaded() -> JSONObject {
        if let values { return values }
        let fileManager = FileManager.default
        var result: JSONObject = [:]
        if fileManager.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url),
               let object = try? JSONDecoder().decode(JSONObject.self, from: data) {
                result = object
            } else {
                let aside = url.deletingLastPathComponent()
                    .appending(path: url.lastPathComponent + ".corrupt-\(UUID().uuidString.prefix(8))")
                try? fileManager.moveItem(at: url, to: aside)
            }
        }
        values = result
        return result
    }

    private func writeIfDirty() throws {
        guard dirty, let values else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(values)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appending(path: ".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temporary)
        guard rename(temporary.path, url.path) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)])
        }
        dirty = false
        writeCount += 1
    }
}
