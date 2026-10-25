@testable import AletheIntegrations
import Foundation
import Testing

@Suite struct McpStoreSyncTests {
    @Test func syncReportsWrittenBlockedSkippedAndFailed() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("home/.codex/config.toml", """
            [mcp_servers.swarm]
            command = "npx"
            env_vars = ["SESSION"]

            """)
        box.write("home/.config/opencode/opencode.json", "{}")

        let outcomes = try box.store.syncNow(name: "swarm", from: .codex, to: [.codex, .claude, .opencode, .opencode],
                                             scope: .global, repository: nil)
        #expect(outcomes.map(\.agent) == [.claude, .opencode])
        #expect(outcomes[0].status == .blocked([McpUnsupportedField(agent: .claude, field: "env.SESSION", detail: "SESSION")]))
        guard case .written(let url) = outcomes[1].status else {
            Issue.record("expected a write")
            return
        }
        #expect(url.lastPathComponent == "opencode.json")
        #expect(box.read("home/.config/opencode/opencode.json")?.contains("{env:SESSION}") == true)

        let again = try box.store.syncNow(name: "swarm", from: .codex, to: [.opencode], scope: .global, repository: nil)
        #expect(again[0].status == .skipped)
        let forced = try box.store.syncNow(name: "swarm", from: .codex, to: [.opencode], scope: .global, repository: nil, overwrite: true)
        guard case .written = forced[0].status else {
            Issue.record("expected an overwrite")
            return
        }
    }

    @Test func syncCopiesSecretsWithoutTheCaller() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("home/.codex/config.toml", McpStoreFixtures.codexRealShape)
        let outcomes = try box.store.syncNow(name: "discord", from: .codex, to: [.cursor], scope: .global, repository: nil)
        guard case .written = outcomes[0].status else {
            Issue.record("expected a write")
            return
        }
        #expect(box.read("home/.cursor/mcp.json")?.contains("a-live-secret-token-value") == true)
    }

    @Test func syncFailsPerTargetAndNeedsTheSource() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("repo/.mcp.json", #"{"mcpServers":{"a":{"command":"x"}}}"#)
        let outcomes = try box.store.syncNow(name: "a", from: .claude, to: [.antigravity], scope: .project, repository: box.repo)
        #expect(outcomes == [McpSyncOutcome(agent: .antigravity, status: .failed(.unsupportedScope))])
        #expect(throws: McpStoreError.notFound) {
            try box.store.syncNow(name: "ghost", from: .claude, to: [.codex], scope: .project, repository: box.repo)
        }
    }

    @Test func groupsReportGapsOnlyForReadableAgents() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("home/.claude.json", #"{"mcpServers":{"figma":{"url":"https://f"}}}"#)
        box.write("home/.codex/config.toml", "[mcp_servers.figma]\nurl = \"https://f\"\nenabled = false\n\n[mcp_servers.swarm]\ncommand = \"x\"\n")
        box.write("home/.cursor/mcp.json", "{ broken")

        let groups = McpStore.groups(try box.store.scanNow(scope: .global, repository: nil))
        #expect(groups.map(\.name) == ["figma", "swarm"])
        #expect(groups[0].agents == [.claude, .codex])
        #expect(groups[0].missingAgents == [.opencode, .antigravity])
        #expect(groups[0].hasDisabled)
        #expect(groups[1].missingAgents == [.claude, .opencode, .antigravity])
        #expect(McpStore.groups([McpAgentSnapshot(agent: .claude, scope: .global)]).isEmpty)

        let results = box.store.syncAllNow(groups, scope: .global, repository: nil)
        #expect(results.map(\.name) == ["figma", "swarm"])
        let after = McpStore.groups(try box.store.scanNow(scope: .global, repository: nil))
        #expect(after.allSatisfy { $0.missingAgents.isEmpty })
    }

    @Test func revealReturnsOneLiteral() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("home/.codex/config.toml", McpStoreFixtures.codexRealShape)
        box.write("home/.cursor/mcp.json", #"{"mcpServers":{"r":{"url":"https://r","headers":{"Authorization":"Bearer abc"}}}}"#)

        #expect(try box.store.revealNow(agent: .codex, scope: .global, repository: nil, name: "discord", key: "DISCORD_TOKEN")
            == "a-live-secret-token-value")
        #expect(try box.store.revealNow(agent: .cursor, scope: .global, repository: nil, name: "r", key: "Authorization", header: true)
            == "Bearer abc")
        #expect(throws: McpStoreError.notFound) {
            try box.store.revealNow(agent: .codex, scope: .global, repository: nil, name: "discord", key: "DISCORD_TOKEN", header: true)
        }
        #expect(throws: McpStoreError.notFound) {
            try box.store.revealNow(agent: .codex, scope: .global, repository: nil, name: "discord", key: "MISSING")
        }
    }

    @Test func restorePutsABackupBackAndCanBeUndone() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let config = box.write("home/.codex/config.toml", McpStoreFixtures.codexRealShape)
        let source = McpStoreFixtures.fileSource(config, .user)
        let report = try box.store.apply(.remove(name: "discord"), agent: .codex, to: source)
        let backup = try #require(report.backup)

        let restored = try box.store.restoreNow(backup, agent: .codex, source: source)
        #expect(box.read("home/.codex/config.toml") == McpStoreFixtures.codexRealShape)
        #expect(restored.backup != nil)

        #expect(throws: McpStoreError.backupMismatch) {
            try box.store.restoreNow(backup, agent: .cursor, source: McpStoreFixtures.fileSource(box.url("home/.cursor/mcp.json"), .user))
        }
    }

    @Test func projectBackupsAreKeptPerRepository() {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let one = box.store.backupSlot(agent: .claude, source: McpStoreFixtures.fileSource(box.url("one/.mcp.json"), .project))
        let two = box.store.backupSlot(agent: .claude, source: McpStoreFixtures.fileSource(box.url("two/.mcp.json"), .project))
        #expect(one != two)
        #expect(one.name.hasPrefix("claude-project_"))
        #expect(box.store.backupSlot(agent: .claude, source: McpStoreFixtures.fileSource(box.url("x"), .local)).name == "claude-local")
    }

    @Test func storeErrorsNeverCarryValues() {
        #expect(McpStoreError.file(.writeFailed(URL(filePath: "/secret"), "detail")).description == "write_failed")
        #expect(McpStoreError.config(.unreadable).description == "unreadable")
    }
}
