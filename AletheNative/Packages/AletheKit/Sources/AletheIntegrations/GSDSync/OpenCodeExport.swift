import Foundation

public enum OpenCodeExportPart: Hashable, Sendable {
    case text(String)
    case reasoning(String)
    case tool(name: String, status: String, input: String?, output: String?)
    case patch
    case other(type: String)
}

public struct OpenCodeExportMessage: Hashable, Sendable, Identifiable {
    public enum Role: String, Hashable, Sendable {
        case user, assistant
    }

    public var id: String
    public var role: Role
    public var createdAt: Date?
    public var completedAt: Date?
    public var modelID: String?
    public var parts: [OpenCodeExportPart]
}

public struct OpenCodeExportSession: Hashable, Sendable {
    public var id: String
    public var title: String?
    public var modelID: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var updatedAt: Date?
    public var messages: [OpenCodeExportMessage]

    public var totalTokens: Int? {
        guard inputTokens != nil || outputTokens != nil else { return nil }
        return (inputTokens ?? 0) + (outputTokens ?? 0)
    }
}

public enum OpenCodeExportError: Error, Equatable, Sendable {
    case invalidSessionID
    case command(ExternalCommandError)
    case failed(status: Int32, stderr: String)
    case notJSON
}

public enum OpenCodeExport {
    public static let timeout: Duration = .seconds(30)

    public static func isValidSessionID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && !id.hasPrefix("-")
            && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-" }
    }

    public static func run(
        sessionID: String,
        directory: URL,
        executable: URL,
        timeout: Duration = timeout
    ) async throws(OpenCodeExportError) -> OpenCodeExportSession {
        guard isValidSessionID(sessionID) else { throw .invalidSessionID }
        let result: ExternalCommandResult
        do {
            result = try await ExternalCommand.run(executable, ["export", sessionID], directory: directory, timeout: timeout)
        } catch {
            throw .command(error)
        }
        guard result.succeeded else { throw .failed(status: result.status, stderr: result.stderr) }
        return try parse(result.stdout)
    }

    public static func parse(_ output: String) throws(OpenCodeExportError) -> OpenCodeExportSession {
        guard let start = output.firstIndex(of: "{"),
              let root = try? JSONSerialization.jsonObject(with: Data(output[start...].utf8)) as? [String: Any] else {
            throw .notJSON
        }
        let info = root["info"] as? [String: Any] ?? [:]
        let model = info["model"] as? [String: Any]
        let tokens = info["tokens"] as? [String: Any]
        let time = info["time"] as? [String: Any]
        let messages = (root["messages"] as? [[String: Any]] ?? []).compactMap(message)
        return OpenCodeExportSession(
            id: info["id"] as? String ?? "",
            title: info["title"] as? String,
            modelID: model?["id"] as? String,
            inputTokens: int(tokens?["input"]),
            outputTokens: int(tokens?["output"]),
            updatedAt: date(time?["updated"]),
            messages: messages
        )
    }

    static func message(_ object: [String: Any]) -> OpenCodeExportMessage? {
        guard let info = object["info"] as? [String: Any],
              let id = info["id"] as? String,
              let role = (info["role"] as? String).flatMap(OpenCodeExportMessage.Role.init(rawValue:)) else { return nil }
        let time = info["time"] as? [String: Any]
        let model = info["model"] as? [String: Any]
        return OpenCodeExportMessage(
            id: id,
            role: role,
            createdAt: date(time?["created"]),
            completedAt: date(time?["completed"]),
            modelID: model?["modelID"] as? String,
            parts: (object["parts"] as? [[String: Any]] ?? []).map(part)
        )
    }

    static func part(_ object: [String: Any]) -> OpenCodeExportPart {
        let type = object["type"] as? String ?? ""
        if case "text" = type {
            return .text(object["text"] as? String ?? "")
        } else if case "reasoning" = type {
            return .reasoning(object["text"] as? String ?? "")
        } else if case "tool" = type {
            let state = object["state"] as? [String: Any] ?? [:]
            return .tool(
                name: object["tool"] as? String ?? "",
                status: state["status"] as? String ?? "",
                input: (state["input"] as? [String: Any]).flatMap(toolInput),
                output: state["output"] as? String
            )
        } else if case "patch" = type {
            return .patch
        } else {
            return .other(type: type)
        }
    }

    static func toolInput(_ input: [String: Any]) -> String? {
        if let description = input["description"] as? String { return description }
        guard let data = try? JSONSerialization.data(
            withJSONObject: input, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
    }
}
