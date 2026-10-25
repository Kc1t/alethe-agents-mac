import Foundation

public protocol VersionedDocument: Codable, Sendable, Equatable {
    static var currentVersion: Int { get }
    static var migrations: [Int: @Sendable (inout JSONObject) throws -> Void] { get }
    static var initial: Self { get }
    var schemaVersion: Int { get set }
}

public enum DocumentLoadOutcome: Equatable, Sendable {
    case fresh
    case loaded
    case migrated(from: Int, backup: URL)
    case recoveredFromCorruption(movedTo: URL)
}

public enum DocumentStoreError: Error, Equatable {
    case newerVersion(found: Int, supported: Int)
    case missingMigration(from: Int)
}

public actor DocumentStore<Document: VersionedDocument> {
    public let url: URL
    private let debounce: Duration
    private var pending: (document: Document, sequence: UInt64)?
    private var lastWrittenSequence: UInt64 = 0
    private var debounceTask: Task<Void, Never>?
    private var readOnly = false

    public init(url: URL, debounce: Duration = .milliseconds(300)) {
        self.url = url
        self.debounce = debounce
    }

    public func load() throws -> (document: Document, outcome: DocumentLoadOutcome) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return (Document.initial, .fresh)
        }
        let data: Data
        var object: JSONObject
        do {
            data = try Data(contentsOf: url)
            object = try JSONDecoder().decode(JSONObject.self, from: data)
        } catch {
            return (Document.initial, .recoveredFromCorruption(movedTo: try quarantine()))
        }
        guard let version = object["schemaVersion"]?.intValue else {
            return (Document.initial, .recoveredFromCorruption(movedTo: try quarantine()))
        }
        if version > Document.currentVersion {
            readOnly = true
            throw DocumentStoreError.newerVersion(found: version, supported: Document.currentVersion)
        }

        var outcome = DocumentLoadOutcome.loaded
        if version < Document.currentVersion {
            let backup = siblingURL(suffix: ".v\(version).bak")
            try? fileManager.removeItem(at: backup)
            try fileManager.copyItem(at: url, to: backup)
            for step in version..<Document.currentVersion {
                guard let migrate = Document.migrations[step] else {
                    throw DocumentStoreError.missingMigration(from: step)
                }
                try migrate(&object)
                object["schemaVersion"] = .number(Double(step + 1))
            }
            outcome = .migrated(from: version, backup: backup)
        }

        do {
            let payload: Data
            if version < Document.currentVersion {
                payload = try JSONEncoder().encode(object)
            } else {
                payload = data
            }
            let document = try Self.decoder.decode(Document.self, from: payload)
            if case .migrated = outcome { try write(document) }
            return (document, outcome)
        } catch {
            return (Document.initial, .recoveredFromCorruption(movedTo: try quarantine()))
        }
    }

    public func scheduleSave(_ document: Document, revision: UInt64) {
        guard !readOnly, revision > lastWrittenSequence, revision > (pending?.sequence ?? 0) else { return }
        pending = (document, revision)
        debounceTask?.cancel()
        debounceTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self.flushPending()
        }
    }

    public func flush() {
        debounceTask?.cancel()
        flushPending()
    }

    public func save(_ document: Document, revision: UInt64) throws {
        guard !readOnly, revision > lastWrittenSequence else { return }
        try write(document, sequence: revision)
        if let pending, pending.sequence <= revision { self.pending = nil }
    }

    public var isReadOnly: Bool { readOnly }

    private func flushPending() {
        guard let (document, sequence) = pending else { return }
        do {
            try write(document, sequence: sequence)
            pending = nil
        } catch {
        }
    }

    private func write(_ document: Document, sequence: UInt64? = nil) throws {
        if let sequence {
            guard sequence > lastWrittenSequence else { return }
        }
        var stamped = document
        stamped.schemaVersion = Document.currentVersion
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(stamped).write(to: url, options: .atomic)
        if let sequence { lastWrittenSequence = sequence }
    }

    private func quarantine() throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = siblingURL(suffix: ".corrupt-\(stamp)")
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    private func siblingURL(suffix: String) -> URL {
        url.deletingLastPathComponent().appending(path: url.lastPathComponent + suffix)
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
