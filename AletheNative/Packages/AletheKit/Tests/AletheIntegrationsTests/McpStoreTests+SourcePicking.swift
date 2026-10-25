@testable import AletheIntegrations
import Foundation
import Testing

@Suite struct McpStoreSourcePickingTests {
    @Test func anExistingServerIsEditedWhereItLives() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("repo/.mcp.json", #"{"mcpServers":{"shared":{"command":"x"}}}"#)
        let source = try box.store.pickSource(.claude, scope: .project, repository: box.repo, name: "shared", kind: nil, creating: false)
        #expect(source.kind == .project)
    }

    @Test func aNewServerGoesToTheFirstSource() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let source = try box.store.pickSource(.claude, scope: .project, repository: box.repo, name: "new", kind: nil, creating: true)
        #expect(source.kind == .local)
        #expect(source.projectKey == ClaudeMcpAdapter.projectKey(for: box.repo))
    }

    @Test func aRequestedKindWins() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        let source = try box.store.pickSource(.claude, scope: .project, repository: box.repo, name: "new", kind: .project, creating: true)
        #expect(source.kind == .project)
        #expect(throws: McpStoreError.unsupportedScope) {
            try box.store.pickSource(.codex, scope: .project, repository: box.repo, name: "new", kind: .local, creating: true)
        }
        #expect(throws: McpStoreError.unsupportedScope) {
            try box.store.pickSource(.antigravity, scope: .project, repository: box.repo, name: "new", kind: nil, creating: true)
        }
    }

    @Test func aMissingServerIsNotFoundUnlessCreating() {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("repo/.mcp.json", "{ broken")
        #expect(throws: McpStoreError.notFound) {
            try box.store.pickSource(.claude, scope: .project, repository: box.repo, name: "ghost", kind: nil, creating: false)
        }
    }

    @Test func mutateValidatesAndSetsEnabled() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("home/.config/opencode/opencode.json", #"{"theme":"x"}"#)

        _ = try box.store.mutateNow(.upsert(McpServer(name: "  tool  ", transport: .stdio(command: " npx ", arguments: [], cwd: nil))),
                                    agent: .opencode, scope: .global, repository: nil)
        _ = try box.store.mutateNow(.setEnabled(name: "tool", enabled: false), agent: .opencode, scope: .global, repository: nil)

        let servers = try box.store.scanNow(scope: .global, repository: nil, agents: [.opencode])[0].servers
        #expect(servers.map(\.server.name) == ["tool"])
        #expect(servers[0].server.enabled == false)
        #expect(servers[0].server.transport == .stdio(command: "npx", arguments: [], cwd: nil))
        #expect(box.read("home/.config/opencode/opencode.json")?.contains(#""theme""#) == true)
    }

    @Test func disablingWhereTheAgentCannotIsRefused() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("home/.cursor/mcp.json", #"{"mcpServers":{"a":{"command":"x"}}}"#)
        #expect(throws: McpStoreError.config(.unsupportedDisable)) {
            try box.store.mutateNow(.setEnabled(name: "a", enabled: false), agent: .cursor, scope: .global, repository: nil)
        }
    }

    @Test func antigravityImportsWarn() throws {
        let box = McpStoreFixtures.Sandbox()
        defer { box.cleanUp() }
        box.write("home/.gemini/config/import_manifest.json", #"{"imports":[{"name":"swarm"}]}"#)
        let report = try box.store.mutateNow(
            .upsert(McpStoreFixtures.probe("swarm-tasks")), agent: .antigravity, scope: .global, repository: nil
        )
        #expect(report.warnings == [.managedByImport("swarm")])
    }

    @Test func onlyRemovalNeedsConfirmation() {
        #expect(McpMutation.remove(name: "a").needsConfirmation)
        #expect(!McpMutation.setEnabled(name: "a", enabled: false).needsConfirmation)
        #expect(!McpMutation.upsert(McpStoreFixtures.probe("a")).needsConfirmation)
    }

    @Test func validationRefusesNamesNoConfigCanHold() {
        for name in ["", "  ", "a/b", #"a\b"#, #"a"b"#, "a\nb"] {
            #expect(throws: McpStoreError.invalidName) { try McpStore.validated(McpStoreFixtures.probe(name)) }
        }
        #expect(throws: McpStoreError.invalidCommand) {
            try McpStore.validated(McpServer(name: "a", transport: .stdio(command: "  ", arguments: [], cwd: nil)))
        }
        #expect(throws: McpStoreError.invalidURL) {
            try McpStore.validated(McpServer(name: "a", transport: .http(url: " ", headers: [:])))
        }
    }

    @Test func validationTrimsAndDropsBlankKeys() throws {
        let server = try McpStore.validated(McpServer(
            name: " a ",
            transport: .sse(url: " https://x ", headers: [" ": .literal("v"), "Auth": .literal("t")]),
            env: [" KEY ": .literal("1"), "": .literal("2")]
        ))
        #expect(server.name == "a")
        #expect(server.transport == .sse(url: "https://x", headers: ["Auth": .literal("t")]))
        #expect(server.env == ["KEY": .literal("1")])
    }
}
