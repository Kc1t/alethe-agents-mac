@testable import AletheIntegrations
import Foundation
import Testing

@Suite struct McpStoreGoldenTests {
    @Test func claudeLocalScopeReadsServersFromTheProjectsMap() throws {
        let source = McpStoreFixtures.localSource(
            URL(filePath: "/x/.claude.json"), #"D:\kauam\Documents\Github\Verzel\Retaguarda\Ret-Campanhas"#
        )
        let servers = try ClaudeMcpAdapter().parse(McpStoreFixtures.claudeRealShape, source: source)
        #expect(servers.map(\.name) == ["azure-devops"])
    }

    @Test func claudeGlobalScopeIgnoresTheProjectsMap() throws {
        let servers = try ClaudeMcpAdapter().parse(
            McpStoreFixtures.claudeRealShape, source: McpStoreFixtures.fileSource(URL(filePath: "/x/.claude.json"), .user)
        )
        #expect(servers.map(\.name) == ["higgsfield"])
    }

    @Test func claudeLocalLookupIsSlashAndCaseInsensitive() throws {
        let source = McpStoreFixtures.localSource(
            URL(filePath: "/x/.claude.json"), #"d:\KAUAM\Documents\Github\Verzel\Retaguarda\Ret-Campanhas\"#
        )
        #expect(try ClaudeMcpAdapter().parse(McpStoreFixtures.claudeRealShape, source: source).count == 1)
    }

    @Test func claudeLocalWriteLandsInTheMatchingProjectEntry() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let config = box.write("home/.claude.json", McpStoreFixtures.claudeRealShape)
        let source = McpStoreFixtures.localSource(config, #"D:\kauam\Documents\Github\Verzel\Retaguarda\Ret-Campanhas"#)

        _ = try box.store.apply(.upsert(McpStoreFixtures.probe("alethe-probe")), agent: .claude, to: source)

        let written = try #require(box.read("home/.claude.json"))
        #expect(written.contains("azure-devops"))
        #expect(written.contains("alethe-probe"))
        #expect(written.contains("hasTrustDialogAccepted"))
        #expect(written.contains("numStartups"))
        #expect(try ClaudeMcpAdapter().parse(written, source: McpStoreFixtures.fileSource(config, .user)).map(\.name) == ["higgsfield"])
        #expect(try ClaudeMcpAdapter().parse(written, source: source).count == 2)
    }

    @Test func claudeLocalWriteCreatesTheProjectEntryWhenAbsent() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let config = box.write("home/.claude.json", #"{"numStartups": 3}"#)
        let source = McpStoreFixtures.localSource(config, #"D:\some\new\repo"#)

        _ = try box.store.apply(.upsert(McpStoreFixtures.probe("alethe-probe")), agent: .claude, to: source)

        let written = try #require(box.read("home/.claude.json"))
        #expect(written.contains(#""D:/some/new/repo""#))
        #expect(written.contains("numStartups"))
        #expect(try ClaudeMcpAdapter().parse(written, source: source).count == 1)
    }

    @Test func claudeProjectScopeExposesBothTheLocalAndTheSharedFile() {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let sources = box.store.sources(.claude, .project, box.repo)
        #expect(sources.map(\.kind) == [.local, .project])
        #expect(sources[0].url.lastPathComponent == ".claude.json")
        #expect(sources[1].url.lastPathComponent == ".mcp.json")
    }

    @Test func writingBacksUpAndLeavesTheRestOfTheFileAlone() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let config = box.write("home/.codex/config.toml", McpStoreFixtures.codexRealShape)

        let report = try box.store.apply(
            .upsert(McpStoreFixtures.probe("alethe-probe")), agent: .codex, to: McpStoreFixtures.fileSource(config, .user)
        )

        #expect(report.changed == ["alethe-probe"])
        let backup = try #require(report.backup)
        #expect(try String(contentsOf: backup.url, encoding: .utf8) == McpStoreFixtures.codexRealShape)
        #expect(backup.slot == ConfigBackupSlot(agent: "codex", kind: "user"))
        #expect(backup.url.path.hasPrefix(box.url("profile").path))

        let written = try #require(box.read("home/.codex/config.toml"))
        #expect(written.contains("# hand written"))
        #expect(written.contains(#"[projects."D:\\repo\\one"]"#))
        #expect(written.contains("[[hooks.PreToolUse]]"))
        #expect(written.contains("[mcp_servers.discord.env]"))
        #expect(written.contains("alethe-probe"))
    }

    @Test func removingDropsTheServerAndItsSubtableOnly() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let config = box.write("home/.codex/config.toml", McpStoreFixtures.codexRealShape)

        _ = try box.store.apply(.remove(name: "discord"), agent: .codex, to: McpStoreFixtures.fileSource(config, .user))

        let written = try #require(box.read("home/.codex/config.toml"))
        #expect(!written.contains("a-live-secret-token-value"))
        #expect(!written.contains("[mcp_servers.discord"))
        #expect(written.contains("[[hooks.PreToolUse]]"))
        #expect(written.contains("trust_level"))
    }

    @Test func anUpsertCreatesAMissingProjectConfig() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let config = box.url("repo/.mcp.json")

        let report = try box.store.apply(
            .upsert(McpStoreFixtures.probe("alethe-probe")), agent: .claude, to: McpStoreFixtures.fileSource(config, .project)
        )

        #expect(report.backup == nil)
        let written = try #require(box.read("repo/.mcp.json"))
        #expect(written.contains(#""mcpServers""#))
        #expect(written.contains("alethe-probe"))
    }

    @Test func aFieldTheAgentCannotExpressBlocksTheWrite() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let config = box.write("repo/.mcp.json", "{}")
        var server = McpStoreFixtures.probe("alethe-probe")
        server.env["TOKEN"] = .passthrough("TOKEN")

        #expect(throws: McpStoreError.unsupportedFields([McpUnsupportedField(agent: .claude, field: "env.TOKEN", detail: "TOKEN")])) {
            try box.store.apply(.upsert(server), agent: .claude, to: McpStoreFixtures.fileSource(config, .project))
        }
        do {
            _ = try box.store.apply(.upsert(server), agent: .claude, to: McpStoreFixtures.fileSource(config, .project))
        } catch {
            #expect(error.description == "unsupported_fields:env.TOKEN")
        }
        #expect(box.read("repo/.mcp.json") == "{}")
    }

    @Test func anUnparsableConfigIsNeverWrittenTo() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let config = box.write("repo/opencode.json", #"{"mcp":{}}}}"#)

        do {
            _ = try box.store.apply(
                .upsert(McpStoreFixtures.probe("alethe-probe")), agent: .opencode, to: McpStoreFixtures.fileSource(config, .user)
            )
            Issue.record("expected an error")
        } catch {
            #expect(error.description.hasPrefix("unparsable"))
        }
        #expect(box.read("repo/opencode.json") == #"{"mcp":{}}}}"#)
    }

    @Test func jsoncIsRefusedRatherThanStripped() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let config = box.write("repo/opencode.jsonc", "// keep me\n{\"mcp\":{}}")

        #expect(throws: McpStoreError.config(.jsoncUnsupported)) {
            try box.store.apply(
                .upsert(McpStoreFixtures.probe("alethe-probe")), agent: .opencode, to: McpStoreFixtures.fileSource(config, .user)
            )
        }
        #expect(box.read("repo/opencode.jsonc")?.contains("// keep me") == true)
    }

    @Test func mutatingAMissingFileReportsNotFound() {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        #expect(throws: McpStoreError.notFound) {
            try box.store.apply(
                .remove(name: "ghost"), agent: .codex, to: McpStoreFixtures.fileSource(box.url("home/.codex/config.toml"), .user)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: box.url("home/.codex/config.toml").path))
    }

    @Test func backupsAreCapped() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let config = box.write("home/.codex/config.toml", McpStoreFixtures.codexRealShape)
        let source = McpStoreFixtures.fileSource(config, .user)
        for index in 0..<(ConfigFileWriter.maxBackups + 4) {
            _ = try box.store.apply(.upsert(McpStoreFixtures.probe("probe-\(index)")), agent: .codex, to: source)
        }
        #expect(box.store.backups(agent: .codex, source: source).count == ConfigFileWriter.maxBackups)
    }

    @Test func importOwnerMatchesAPrefixedServerName() {
        #expect(AntigravityMcpAdapter.importOwner(of: "codeagentswarm-tasks", imports: ["codeagentswarm"]) == "codeagentswarm")
        #expect(AntigravityMcpAdapter.importOwner(of: "figma", imports: ["codeagentswarm"]) == nil)
    }

    @Test func requestedAgentsFallsBackToEveryAgent() {
        #expect(McpStore.requestedAgents(nil) == McpAgent.allCases)
        #expect(McpStore.requestedAgents(["nonsense"]) == McpAgent.allCases)
        #expect(McpStore.requestedAgents(["codex"]) == [.codex])
        #expect(McpStore.requestedAgents(["agy"]) == [.antigravity])
    }

    @Test func repositoryPathIgnoresBlankInput() {
        #expect(McpStore.repositoryURL(nil) == nil)
        #expect(McpStore.repositoryURL("   ") == nil)
        #expect(McpStore.repositoryURL("/repo") != nil)
    }

    @Test func scanningGlobalScopeReturnsOneSnapshotPerAgent() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let snapshots = try box.store.scanNow(scope: .global, repository: nil)
        #expect(snapshots.map(\.agent) == McpAgent.allCases)
        #expect(snapshots.allSatisfy { $0.scope == .global })
    }

    @Test func aMissingConfigIsNotAnError() {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let snapshot = box.store.scanAgent(.codex, scope: .project, repository: box.url("not/a/repo"), imports: [])
        #expect(snapshot.sources.count == 1)
        #expect(snapshot.sources[0].exists == false)
        #expect(snapshot.sources[0].parseError == nil)
        #expect(snapshot.servers.isEmpty)
    }

    @Test func antigravityReportsNoProjectConfig() {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let snapshot = box.store.scanAgent(.antigravity, scope: .project, repository: box.repo, imports: [])
        #expect(snapshot.sources.isEmpty)
        #expect(snapshot.servers.isEmpty)
    }
}
