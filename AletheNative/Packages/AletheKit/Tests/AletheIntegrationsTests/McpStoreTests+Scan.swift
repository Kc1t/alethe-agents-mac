import Foundation
import Testing
@testable import AletheIntegrations

@Suite struct McpStoreScanTests {
    @Test func scanReadsEveryAgentsFileAndMarksImports() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("home/.claude.json", McpStoreFixtures.claudeRealShape)
        box.write("home/.codex/config.toml", McpStoreFixtures.codexRealShape)
        box.write("home/.gemini/config/mcp_config.json", #"{"mcpServers":{"codeagentswarm-tasks":{"command":"node"},"figma":{"url":"https://x"}}}"#)
        box.write("home/.gemini/config/import_manifest.json", #"{"imports":[{"name":"codeagentswarm"}]}"#)

        let snapshots = try box.store.scanNow(scope: .global, repository: nil)
        let byAgent = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.agent, $0) })
        #expect(byAgent[.claude]?.servers.map(\.server.name) == ["higgsfield"])
        #expect(byAgent[.codex]?.servers.map(\.server.name) == ["discord"])
        let antigravity = try #require(byAgent[.antigravity])
        #expect(antigravity.servers.first { $0.server.name == "codeagentswarm-tasks" }?.managedByImport == "codeagentswarm")
        #expect(antigravity.servers.first { $0.server.name == "figma" }?.managedByImport == nil)
        #expect(byAgent[.cursor]?.sources.first?.exists == false)
        #expect(byAgent[.cursor]?.sources.first?.writable == false)
        #expect(byAgent[.codex]?.sources.first?.modificationDate != nil)
    }

    @Test func aParseErrorMarksTheSourceUnwritableAndHidesTheContent() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("home/.codex/config.toml", "[mcp_servers.broken\ntoken = \"secret-value\"")

        let snapshot = try #require(try box.store.scanNow(scope: .global, repository: nil, agents: [.codex]).first)
        let source = try #require(snapshot.sources.first)
        #expect(source.exists)
        #expect(!source.writable)
        let error = try #require(source.parseError)
        #expect(!error.description.contains("secret-value"))
        #expect(!snapshot.isReadable)
    }

    @Test func theCacheFollowsTheFileAndWrites() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("repo/.mcp.json", #"{"mcpServers":{"a":{"command":"x"}}}"#)
        let first = try box.store.scanNow(scope: .project, repository: box.repo, agents: [.claude])
        #expect(first[0].servers.map(\.server.name) == ["a"])

        box.write("repo/.mcp.json", #"{"mcpServers":{"a":{"command":"x"},"bb":{"command":"y"}}}"#)
        let second = try box.store.scanNow(scope: .project, repository: box.repo, agents: [.claude])
        #expect(second[0].servers.map(\.server.name) == ["a", "bb"])

        _ = try box.store.mutateNow(.remove(name: "bb"), agent: .claude, scope: .project, repository: box.repo)
        let third = try box.store.scanNow(scope: .project, repository: box.repo, agents: [.claude])
        #expect(third[0].servers.map(\.server.name) == ["a"])
    }

    @Test func configPathsListEverySourceOfTheScope() {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("repo/.mcp.json", "{}")
        let paths = box.store.configPathsNow(scope: .project, repository: box.repo)
        #expect(!paths.contains { $0.agent == .antigravity })
        #expect(paths.first { $0.agent == .claude && $0.kind == .project }?.exists == true)
        #expect(paths.first { $0.agent == .codex }?.exists == false)
        #expect(McpStore.capabilities.map(\.agent) == McpAgent.allCases)
    }
}
