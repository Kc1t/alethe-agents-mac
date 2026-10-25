import Foundation
import Testing
@testable import AletheIntegrations

enum McpStoreFixtures {
    static let codexRealShape = #"""
    # hand written
    model = "gpt-5.6-sol"

    [projects."D:\\repo\\one"]
    trust_level = "trusted"

    [mcp_servers.discord]
    command = "npx"
    args = ["-y", "@quadslab.io/discord-mcp"]

    [mcp_servers.discord.env]
    DISCORD_TOKEN = "a-live-secret-token-value"

    [[hooks.PreToolUse]]
    name = "gate"

    """#

    static let claudeRealShape = #"""
    {
      "numStartups": 1871,
      "mcpServers": {
        "higgsfield": { "type": "http", "url": "https://mcp.higgsfield.ai/mcp" }
      },
      "projects": {
        "D:/kauam/Documents/Github/Verzel/Retaguarda/Ret-Campanhas": {
          "allowedTools": [],
          "mcpServers": {
            "azure-devops": {
              "type": "stdio",
              "command": "npx",
              "args": ["-y", "@azure-devops/mcp", "GrupoAvenida"],
              "env": {}
            }
          },
          "hasTrustDialogAccepted": true
        }
      }
    }
    """#

    struct Sandbox {
        let root: URL
        let store: McpStore

        init() {
            root = FileManager.default.temporaryDirectory
                .appending(path: "AletheMcpStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: root.appending(path: "home"), withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: root.appending(path: "repo"), withIntermediateDirectories: true)
            store = McpStore(home: McpHome(home: root.appending(path: "home", directoryHint: .isDirectory)),
                             writer: ConfigFileWriter(profileDirectory: root.appending(path: "profile")))
        }

        var repo: URL { root.appending(path: "repo", directoryHint: .isDirectory) }

        func url(_ relative: String) -> URL { root.appending(path: relative) }

        @discardableResult
        func write(_ relative: String, _ text: String) -> URL {
            let file = url(relative)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: file)
            return file
        }

        func read(_ relative: String) -> String? {
            try? String(contentsOf: url(relative), encoding: .utf8)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    static func probe(_ name: String) -> McpServer {
        McpServer(name: name, transport: .stdio(command: "node", arguments: ["-e", "0"], cwd: nil))
    }

    static func fileSource(_ url: URL, _ kind: McpSourceKind) -> McpSource {
        McpSource(url: url, kind: kind)
    }

    static func localSource(_ url: URL, _ key: String) -> McpSource {
        McpSource(url: url, kind: .local, projectKey: key)
    }

}
