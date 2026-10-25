import Foundation
import Testing
import AletheAgents
import AletheIntegrations
@testable import AletheOrchestrator

private func workspace(_ tag: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "alethe-fitness-\(tag)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeCore() -> OrchestratorCore {
    var launchers = WorkerLaunchers()
    launchers.set(Launcher(kind: WorkerAgent.codex, program: URL(filePath: "/bin/sleep"), arguments: ["60"]))
    launchers.set(Launcher(kind: WorkerAgent.claude, program: URL(filePath: "/bin/sleep"), arguments: ["60"]))
    return OrchestratorCore(configuration: .init(
        launchers: launchers,
        uncommittedDiff: { _ in nil },
        terminationGrace: .milliseconds(500)
    ))
}

private func call(_ core: OrchestratorCore, _ name: String, _ arguments: OrderedJSON) async throws -> OrderedJSONObject {
    let body: OrderedJSON = [
        "jsonrpc": "2.0", "id": 10, "method": "tools/call",
        "params": ["name": .string(name), "arguments": arguments],
    ]
    let raw = try #require(await OrchestratorMCP.handle(body: body.compactRendered(), planner: nil, handler: core))
    let result = try #require(try OrderedJSON.parse(raw).objectValue?["result"]?.objectValue)
    let text = try #require(result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
    if result["isError"] == true { return ["error": .string(text)] }
    return try #require(try OrderedJSON.parse(text).objectValue)
}

private func delegate(_ core: OrchestratorCore, _ task: String, in folder: URL, agent: String) async throws -> String {
    let delegated = try await call(core, "alethe_delegate", ["tasks": [.string(task)], "cwd": .string(folder.path), "agent": .string(agent)])
    return try #require(delegated["jobs"]?.arrayValue?.first?.objectValue?["id"]?.stringValue, "\(delegated)")
}

private func routing(_ core: OrchestratorCore, _ id: String) async -> OrderedJSONObject? {
    await core.snapshot().jobs.first { $0.id == id }?.routing?.objectValue
}

private func finish(_ core: OrchestratorCore, _ ids: [String], _ folder: URL?) async throws {
    _ = try await call(core, "alethe_cancel", ["jobIds": .array(ids.map(OrderedJSON.string))])
    await core.shutdown()
    if let folder { try? FileManager.default.removeItem(at: folder) }
}

private func fitness(_ worst: String, _ used: Int, plan: String? = nil, rateLimited: Bool = false) -> AgentFitness {
    AgentFitness(worst: worst, used: used, plan: plan, rateLimited: rateLimited)
}

@Suite(.timeLimit(.minutes(1))) struct OrchestratorFitnessTests {
    @Test func everyToolResponseCarriesTheCurrentHeadroom() async throws {
        let core = makeCore()
        await core.setAgentFitness("claude", fitness("week", 19))
        await core.setAgentFitness("codex", fitness("week", 60, plan: "plus"))

        let status = try await call(core, "alethe_status", [:])
        let block = status["fitness"]?.objectValue
        #expect(block?["headroom"] == "claude", "\(status)")
        #expect(block?["codex"]?.objectValue?["plan"] == "plus", "\(status)")

        let checked = try await call(core, "alethe_check", [:])
        #expect(checked["fitness"]?.objectValue?["headroom"] == "claude",
                "alethe_check is the one response the planner must read: \(checked)")
        await core.shutdown()
    }

    @Test func theWorstWindowDecidesHeadroom() async throws {
        let core = makeCore()
        await core.setAgentFitness("claude", fitness("week", 19))
        await core.setAgentFitness("codex", fitness("week", 60))
        let status = try await call(core, "alethe_status", [:])
        #expect(status["fitness"]?.objectValue?["headroom"] == "claude", "\(status)")
        await core.shutdown()
    }

    @Test func delegatingToAnExhaustedAgentNamesTheOtherSide() async throws {
        let folder = try workspace("headroom-hint")
        let core = makeCore()
        await core.setAgentFitness("claude", fitness("week", 12))
        await core.setAgentFitness("codex", fitness("week", 91))

        let delegated = try await call(core, "alethe_delegate", ["tasks": ["something"], "cwd": .string(folder.path), "agent": "codex"])
        let hint = delegated["headroomHint"]?.objectValue
        #expect(hint?["agent"] == "claude", "\(delegated)")
        let reason = hint?["reason"]?.stringValue ?? ""
        #expect(reason.contains("91"), "the hint hides the number it is grounded in: \(reason)")

        let id = delegated["jobs"]?.arrayValue?.first?.objectValue?["id"]?.stringValue
        try await finish(core, id.map { [$0] } ?? [], folder)
    }

    @Test func aRestedAgentGetsNoHint() async throws {
        let folder = try workspace("headroom-quiet")
        let core = makeCore()
        await core.setAgentFitness("claude", fitness("week", 12))
        await core.setAgentFitness("codex", fitness("week", 40))

        let delegated = try await call(core, "alethe_delegate", ["tasks": ["something"], "cwd": .string(folder.path), "agent": "codex"])
        #expect(delegated["headroomHint"] == nil, "nagged about headroom that is not running out: \(delegated)")

        let id = delegated["jobs"]?.arrayValue?.first?.objectValue?["id"]?.stringValue
        try await finish(core, id.map { [$0] } ?? [], folder)
    }

    @Test func theBoardRecordsWhyAWorkerRanWhereItRan() async throws {
        let folder = try workspace("routing-trace")
        let core = makeCore()
        await core.setAgentFitness("claude", fitness("week", 12))
        await core.setAgentFitness("codex", fitness("week", 91))

        let first = try await delegate(core, "into the strained side", in: folder, agent: "codex")
        let second = try await delegate(core, "into the rested side", in: folder, agent: "claude")

        let ignored = await routing(core, first)
        #expect(ignored?["verdict"] == "ignored")
        #expect(ignored?["used"]?.doubleValue == 91.0)
        #expect(ignored?["used"] == .double(91), "serialized as upstream's float")
        #expect(await routing(core, second)?["verdict"] == "chosen")
        try await finish(core, [first, second], folder)
    }

    @Test func aBoardWithRoomOnBothSidesRecordsNoReason() async throws {
        let folder = try workspace("routing-quiet")
        let core = makeCore()
        await core.setAgentFitness("claude", fitness("week", 12))
        await core.setAgentFitness("codex", fitness("week", 40))

        let id = try await delegate(core, "nothing notable", in: folder, agent: "codex")
        let job = try #require(await core.snapshot().jobs.first { $0.id == id })
        #expect(job.routing == nil, "labelled an edge that had nothing to say: \(job)")
        #expect(job.json.objectValue?["routing"] == .null)
        try await finish(core, [id], folder)
    }

    @Test func withBothSidesStrainedTheBoardBlamesTheWorseOne() async throws {
        let folder = try workspace("routing-both-strained")
        let core = makeCore()
        await core.setAgentFitness("claude", fitness("5h", 80))
        await core.setAgentFitness("codex", fitness("5h", 98))

        var ids: [String] = []
        for _ in 0..<5 {
            let id = try await delegate(core, "work", in: folder, agent: "codex")
            let note = await routing(core, id)
            #expect(note?["agent"] == "codex", "named the less strained side, or a different one each call: \(String(describing: note))")
            #expect(note?["verdict"] == "ignored")
            ids.append(id)
        }
        try await finish(core, ids, folder)
    }

    @Test func aHintNeverPresentsAnEquallyExhaustedAgentAsTheWayOut() async throws {
        let folder = try workspace("hint-both-strained")
        let core = makeCore()
        await core.setAgentFitness("claude", fitness("5h", 80))
        await core.setAgentFitness("codex", fitness("5h", 98))

        let delegated = try await call(core, "alethe_delegate", ["tasks": ["work"], "cwd": .string(folder.path), "agent": "codex"])
        let hint = delegated["headroomHint"]?.objectValue
        #expect(hint?["agent"] == "claude", "\(delegated)")
        #expect(hint?["bothStrained"] == true, "\(delegated)")
        let reason = hint?["reason"]?.stringValue ?? ""
        #expect(reason.contains("both are running out"),
                "recommended a side that is itself at the ceiling without saying so: \(reason)")

        let id = delegated["jobs"]?.arrayValue?.first?.objectValue?["id"]?.stringValue
        try await finish(core, id.map { [$0] } ?? [], folder)
    }

    @Test func aRateLimitedAgentOutranksAnyPercentage() async throws {
        let core = makeCore()
        await core.setAgentFitness("claude", fitness("5h", 99))
        await core.setAgentFitness("codex", fitness("5h", 10, rateLimited: true))
        let status = try await call(core, "alethe_status", [:])
        #expect(status["fitness"]?.objectValue?["headroom"] == "claude",
                "sent work to a side that is already refusing it: \(status)")
        await core.shutdown()
    }

    @Test func withoutReadingsResponsesCarryNoFitness() async throws {
        let core = makeCore()
        let status = try await call(core, "alethe_status", [:])
        #expect(status["fitness"] == nil, "\(status)")
        await core.shutdown()
    }

    @Test func aFailedToolCarriesNoFitness() async throws {
        let core = makeCore()
        await core.setAgentFitness("claude", fitness("5h", 10))
        let result = try await call(core, "alethe_delegate", ["tasks": []])
        #expect(result["error"] != nil, "\(result)")
        #expect(result["fitness"] == nil)
        await core.shutdown()
    }

    @Test func aUsageReadingIsPushedUnderItsAgentsName() async throws {
        let core = makeCore()
        let usage = ProviderUsage(agent: .codex, status: .ready, windows: [
            UsageWindow(label: "5h", usedPercent: 30, resetsAt: nil),
            UsageWindow(label: "7d", usedPercent: 70, resetsAt: nil),
        ], plan: "pro")
        let pushed = await core.setAgentFitness(from: usage)
        var expected = AgentFitness(worst: "week", used: 70, plan: "pro")
        expected.windows = ["5h": 30, "week": 70]
        #expect(pushed == expected)
        #expect(await core.agentFitness()["codex"] == pushed)

        #expect(await core.setAgentFitness(from: ProviderUsage(agent: .codex, status: .unavailable("network"))) == nil)
        #expect(await core.agentFitness()["codex"] == pushed)
        await core.shutdown()
    }

    @Test func theBlockReadsTheSameOnEveryCall() async throws {
        let core = makeCore()
        await core.setAgentFitness("codex", fitness("5h", 50))
        await core.setAgentFitness("claude", fitness("5h", 50))
        let first = try await call(core, "alethe_status", [:])["fitness"]
        let second = try await call(core, "alethe_status", [:])["fitness"]
        #expect(first == second)
        #expect(first?.objectValue?.keys == ["claude", "codex", "headroom"])
        #expect(first?.objectValue?["headroom"] == "claude")
        await core.shutdown()
    }
}
