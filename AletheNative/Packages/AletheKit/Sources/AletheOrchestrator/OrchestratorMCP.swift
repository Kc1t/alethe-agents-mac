import AletheIntegrations
import Foundation

public protocol OrchestratorToolHandler: Sendable {
    func callTool(name: String, arguments: OrderedJSONObject, planner: String?) async throws -> OrderedJSON
}

public struct OrchestratorToolError: Error, Hashable, Sendable, CustomStringConvertible {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

public enum OrchestratorMCP {
    public static let serverName = "alethe"
    public static let defaultProtocolVersion = "2025-06-18"

    public static let tools: OrderedJSON = {
        guard let url = resourceBundle.url(forResource: "orchestrator-tools", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tools = try? OrderedJSON.parse(data)
        else {
            assertionFailure("orchestrator-tools.json is missing or unreadable")
            return .array([])
        }
        return tools
    }()

    static var resourceBundle: Bundle {
        let name = "AletheKit_AletheOrchestrator.bundle"
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            for folder in [executable.appending(path: "../Resources"), executable] {
                if let bundle = Bundle(url: folder.appending(path: name).standardizedFileURL) { return bundle }
            }
        }
        return Bundle.module
    }

    public static func handle(
        body: String,
        planner: String?,
        handler: some OrchestratorToolHandler
    ) async -> String? {
        guard let message = (try? OrderedJSON.parse(body))?.objectValue, let id = message["id"] else { return nil }
        let method = message["method"]?.stringValue ?? ""
        let params = message["params"]?.objectValue ?? [:]

        let response: OrderedJSON
        if case "initialize" = method {
            response = result(id: id, [
                "protocolVersion": .string(params["protocolVersion"]?.stringValue ?? defaultProtocolVersion),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": .string(serverName), "title": "Alethe", "version": "1"],
            ])
        } else if case "tools/list" = method {
            response = result(id: id, ["tools": tools])
        } else if case "tools/call" = method {
            let name = params["name"]?.stringValue ?? ""
            let arguments = params["arguments"]?.objectValue ?? [:]
            do {
                let value = try await handler.callTool(name: name, arguments: arguments, planner: planner)
                response = result(id: id, ["content": [["type": "text", "text": .string(value.compactRendered())]]])
            } catch {
                let reason = (error as? OrchestratorToolError)?.message ?? String(describing: error)
                response = result(id: id, [
                    "content": [["type": "text", "text": .string("error: \(reason)")]],
                    "isError": true,
                ])
            }
        } else if case "ping" = method {
            response = result(id: id, [:])
        } else {
            response = [
                "jsonrpc": "2.0",
                "id": id,
                "error": ["code": -32601, "message": .string("unknown method \(method)")],
            ]
        }
        return response.compactRendered()
    }

    public static func handle(
        body: Data,
        planner: String?,
        handler: some OrchestratorToolHandler
    ) async -> String? {
        await handle(body: String(decoding: body, as: UTF8.self), planner: planner, handler: handler)
    }

    private static func result(id: OrderedJSON, _ result: OrderedJSONObject) -> OrderedJSON {
        ["jsonrpc": "2.0", "id": id, "result": .object(result)]
    }
}
