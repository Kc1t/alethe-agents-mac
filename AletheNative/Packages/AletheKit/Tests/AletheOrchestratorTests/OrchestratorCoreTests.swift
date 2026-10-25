import Darwin
import Foundation
import Synchronization
import Testing
import AletheIntegrations
@testable import AletheOrchestrator

private func temporaryDirectory(_ tag: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "alethe-orch-\(tag)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func silentLauncher() -> Launcher {
    Launcher(kind: WorkerAgent.codex, program: URL(filePath: "/bin/sleep"), arguments: ["60"])
}

private func fakeCodexLauncher(in folder: URL, turnSeconds: Int = 1) throws -> Launcher {
    let script = folder.appending(path: "fake-codex.sh")
    try """
    n=0
    while IFS= read -r line; do
      case "$line" in
        *'"method":"thread/start"'*)
          printf '{"id":2,"result":{"thread":{"id":"thread-%s"}}}\\n' "$$" ;;
        *'"method":"turn/start"'*)
          n=$((n+1))
          printf '{"method":"turn/started","params":{"turn":{"id":"turn-%s"}}}\\n' "$n"
          sleep \(turnSeconds)
          printf '{"method":"item/completed","params":{"item":{"type":"agentMessage","text":"done by %s"}}}\\n' "$$"
          printf '{"method":"turn/completed","params":{}}\\n' ;;
      esac
    done
    """.write(to: script, atomically: true, encoding: .utf8)
    return Launcher(kind: WorkerAgent.codex, program: URL(filePath: "/bin/sh"), arguments: [script.path])
}

private func fakeClaudeLauncher() -> Launcher {
    let script = #"""
    while IFS= read -r line; do
      printf '{"type":"system","subtype":"init","session_id":"session-%s"}\n' "$$"
      printf '{"type":"result","is_error":false,"result":"ok"}\n'
    done
    """#
    return Launcher(kind: WorkerAgent.claude, program: URL(filePath: "/bin/sh"), arguments: ["-c", script])
}

private func makeCore(
    _ launchers: [Launcher] = [],
    limit: Int = OrchestratorLimits.defaultConcurrency,
    store: OrchestratorJobStore? = nil
) -> OrchestratorCore {
    var configured = WorkerLaunchers()
    for launcher in launchers { configured.set(launcher) }
    return OrchestratorCore(configuration: .init(
        launchers: configured,
        concurrencyLimit: limit,
        store: store,
        uncommittedDiff: { _ in nil },
        terminationGrace: .milliseconds(500)
    ))
}

private func call(_ core: OrchestratorCore, _ name: String, _ arguments: OrderedJSON, planner: String? = nil) async throws -> OrderedJSONObject {
    let body: OrderedJSON = [
        "jsonrpc": "2.0", "id": 10, "method": "tools/call",
        "params": ["name": .string(name), "arguments": arguments],
    ]
    let raw = try #require(await OrchestratorMCP.handle(body: body.compactRendered(), planner: planner, handler: core))
    let result = try #require(try OrderedJSON.parse(raw).objectValue?["result"]?.objectValue)
    let text = try #require(result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
    if result["isError"] == true { return ["error": .string(text)] }
    return (try? OrderedJSON.parse(text).objectValue) ?? ["raw": .string(text)]
}

private func deliveries(_ checked: OrderedJSONObject) -> [OrderedJSONObject] {
    checked["deliveries"]?.arrayValue?.compactMap(\.objectValue) ?? []
}

private final class PeakWatcher: Sendable {
    private let peak = Mutex(0)
    private let task: Mutex<Task<Void, Never>?> = Mutex(nil)

    init(_ core: OrchestratorCore) {
        let sampler = Task { [weak self] in
            while !Task.isCancelled {
                let running = await core.counts().running
                self?.peak.withLock { $0 = max($0, running) }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        task.withLock { $0 = sampler }
    }

    func finish() -> Int {
        task.withLock { $0?.cancel() }
        return peak.withLock { $0 }
    }
}

private func gone(_ pid: pid_t) -> Bool {
    Darwin.kill(pid, 0) != 0 && errno == ESRCH
}

@Suite(.timeLimit(.minutes(1))) struct OrchestratorCoreTests {
    @Test func aSettledWorkerReportsItsOwnOutcome() async throws {
        let folder = try temporaryDirectory("report")
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore([silentLauncher()])
        _ = try await call(core, "alethe_delegate", [
            "tasks": ["do the thing"], "cwd": .string(folder.path), "timeoutSeconds": 1,
        ])
        _ = try await call(core, "alethe_check", ["wait": true, "timeoutMs": 20000])
        let job = try #require(await core.snapshot().jobs.first)
        #expect(job.status == .failed)
        #expect(!job.summary.isEmpty, "a settled job must keep its report")
        #expect(job.summary != "do the thing", "the report is what the worker said, never an echo of the task")
        await core.shutdown()
    }

    @Test func delegatingNothingIsAnError() async throws {
        let core = makeCore()
        let result = try await call(core, "alethe_delegate", ["tasks": []])
        #expect(result["error"]?.stringValue?.contains("at least one") == true, "\(result)")
    }

    @Test func checkingWithNoWorkReturnsAtOnce() async throws {
        let core = makeCore()
        let started = ContinuousClock.now
        let result = try await call(core, "alethe_check", ["wait": true])
        #expect(result["workersStillBusy"] == 0, "\(result)")
        #expect(deliveries(result).isEmpty)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func aJobFailsCleanlyWhenNoLauncherIsConfigured() async throws {
        let folder = try temporaryDirectory("nolauncher")
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore()
        let delegated = try await call(core, "alethe_delegate", ["cwd": .string(folder.path), "tasks": ["anything"]])
        #expect(delegated["accepted"] == 1, "\(delegated)")

        let checked = try await call(core, "alethe_check", ["wait": true, "timeoutMs": 5000])
        let delivered = deliveries(checked)
        #expect(delivered.count == 1, "\(checked)")
        #expect(delivered.first?["outcome"] == "failed")
        #expect(delivered.first?["text"]?.stringValue?.contains("launcher") == true, "\(checked)")
        #expect(checked["workersStillBusy"] == 0)
    }

    @Test func theObserverSeesEveryStateChange() async throws {
        let folder = try temporaryDirectory("observer")
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore()
        let snapshots = await core.snapshots(bufferingPolicy: .unbounded)
        _ = try await call(core, "alethe_delegate", ["cwd": .string(folder.path), "tasks": ["anything"]])

        var seen: [OrchestratorSnapshot] = []
        for await snapshot in snapshots {
            seen.append(snapshot)
            if snapshot.jobs.first?.status.settled == true { break }
        }
        #expect(seen.count > 1, "the observer saw the initial state only")
        #expect(seen.last?.jobs.isEmpty == false)
        #expect(seen.contains { $0.jobs.first?.status == .queued }, "the queued job was published before it settled")
    }

    @Test func twoWorkersOverlapAndCheckWaitsForBoth() async throws {
        let folder = try temporaryDirectory("parallel")
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore([try fakeCodexLauncher(in: folder)])
        let watcher = PeakWatcher(core)

        let delegated = try await call(core, "alethe_delegate", [
            "cwd": .string(folder.path),
            "tasks": ["Create ALPHA.txt.", "Create BETA.txt."],
        ])
        #expect(delegated["accepted"] == 2, "\(delegated)")

        let checked = try await call(core, "alethe_check", ["wait": true, "timeoutMs": 30000])
        let peak = watcher.finish()
        #expect(checked["workersStillBusy"] == 0, "untilAllSettled returned early: \(checked)")
        #expect(deliveries(checked).count == 2, "both workers must land in one call: \(checked)")
        #expect(deliveries(checked).allSatisfy { $0["outcome"] == "succeeded" }, "\(checked)")
        #expect(peak == 2, "the workers never overlapped")
        await core.shutdown()
    }

    @Test func theQueueNeverBreachesTheConcurrencyLimit() async throws {
        let folder = try temporaryDirectory("queue")
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore([try fakeCodexLauncher(in: folder)], limit: 2)
        let watcher = PeakWatcher(core)

        let delegated = try await call(core, "alethe_delegate", [
            "cwd": .string(folder.path),
            "tasks": .array((1...4).map { .string("Create Q\($0).txt.") }),
        ])
        #expect(delegated["accepted"] == 4, "\(delegated)")

        let counts = await core.counts()
        #expect(counts.running <= 2, "started \(counts.running) workers over the limit")
        #expect(counts.queued == 2, "the remainder must queue")

        let checked = try await call(core, "alethe_check", ["wait": true, "timeoutMs": 30000])
        let peak = watcher.finish()
        #expect(peak == 2, "the limit was breached, peak was \(peak)")
        #expect(deliveries(checked).count == 4, "every queued job must drain: \(checked)")
        await core.shutdown()
    }

    @Test func delegatingToAnUnconfiguredAgentFailsCleanlyLikeAnyOtherAgent() async throws {
        let folder = try temporaryDirectory("claude-unconfigured")
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore()
        let delegated = try await call(core, "alethe_delegate", [
            "tasks": ["anything"], "cwd": .string(folder.path), "agent": "claude",
        ])
        #expect(delegated["accepted"] == 1, "\(delegated)")

        let checked = try await call(core, "alethe_check", ["wait": true, "timeoutMs": 5000])
        let delivered = deliveries(checked)
        #expect(delivered.count == 1, "\(checked)")
        #expect(delivered.first?["outcome"] == "failed")
        #expect(delivered.first?["text"]?.stringValue?.contains("claude") == true, "\(checked)")
    }

    @Test func aWorkerThatNeverFinishesIsStoppedByItsBudget() async throws {
        let folder = try temporaryDirectory("timeout")
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore([silentLauncher()])
        let delegated = try await call(core, "alethe_delegate", [
            "cwd": .string(folder.path), "tasks": ["hang forever"], "timeoutSeconds": 2,
        ])
        #expect(delegated["accepted"] == 1, "\(delegated)")
        #expect(delegated["timeoutSeconds"] == 2, "\(delegated)")

        let checked = try await call(core, "alethe_check", ["wait": true, "timeoutMs": 30000])
        let delivered = deliveries(checked)
        #expect(delivered.count == 1, "\(checked)")
        #expect(delivered.first?["outcome"] == "timeout", "\(checked)")
        #expect(checked["workersStillBusy"] == 0, "the slot must be freed: \(checked)")
        #expect(await core.workerPIDs.isEmpty, "the stopped worker's process is gone")
        await core.shutdown()
    }

    @Test func historyOutlivesTheProcessAndInFlightWorkIsNotReportedAsRunning() async throws {
        let folder = try temporaryDirectory("persist")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OrchestratorJobStore(profileDirectory: folder)
        let first = makeCore([silentLauncher()], store: store)
        _ = try await call(first, "alethe_delegate", ["tasks": ["keep this"], "cwd": .string(folder.path), "label": "a run"])
        await store.flush()
        #expect(FileManager.default.fileExists(atPath: store.url.path), "the store must be written as work is created")

        let second = makeCore(store: OrchestratorJobStore(profileDirectory: folder))
        await second.restore()
        let snapshot = await second.snapshot()
        #expect(snapshot.jobs.count == 1, "the record survives a new process")
        #expect(snapshot.jobs.first?.spec == "keep this")
        #expect(snapshot.jobs.first?.runLabel == "a run")
        #expect(snapshot.jobs.first?.status == .interrupted, "a worker whose process is gone must not be shown as running")
        #expect(snapshot.running == 0, "restored work holds no slot")
        await first.shutdown()
    }

    @Test func aNewIDNeverCollidesWithARestoredOne() async throws {
        let folder = try temporaryDirectory("persist-ids")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OrchestratorJobStore(profileDirectory: folder)
        let first = makeCore([silentLauncher()], store: store)
        _ = try await call(first, "alethe_delegate", ["tasks": ["one", "two"], "cwd": .string(folder.path)])
        await store.flush()

        let second = makeCore([silentLauncher()], store: OrchestratorJobStore(profileDirectory: folder))
        await second.restore()
        let created = try await call(second, "alethe_delegate", ["tasks": ["three"], "cwd": .string(folder.path)])
        #expect(created["jobs"]?.arrayValue?.first?.objectValue?["id"] == "job-03", "counting resumes past the restored ids")
        #expect(created["runId"] == "run-02")
        await first.shutdown()
        await second.shutdown()
    }

    @Test func pastTheParkedLimitTheEarliestFinishedWorkerIsReleased() async throws {
        let folder = try temporaryDirectory("parked")
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore([fakeClaudeLauncher()], limit: 16)
        let count = OrchestratorLimits.parkedLimit + 1
        _ = try await call(core, "alethe_delegate", [
            "agent": "claude", "cwd": .string(folder.path),
            "tasks": .array((1...count).map { .string("task \($0)") }),
        ])
        let checked = try await call(core, "alethe_check", ["wait": true, "timeoutMs": 20000])
        #expect(deliveries(checked).count == count, "\(checked)")

        let snapshot = await core.snapshot()
        #expect(snapshot.jobs.first?.status == .released, "the earliest parked worker is let go")
        #expect(snapshot.jobs.dropFirst().allSatisfy { $0.status == .done })
        #expect(await core.parkedJobIDs == (2...count).map { OrchestratorID.job(UInt64($0)) })
        #expect(await core.workerPIDs.count == OrchestratorLimits.parkedLimit)
        await core.shutdown()
    }

    @Test func noWorkerProcessOutlivesShutdown() async throws {
        let folder = try temporaryDirectory("shutdown")
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore([silentLauncher()], limit: 1)
        _ = try await call(core, "alethe_delegate", ["tasks": ["one", "two"], "cwd": .string(folder.path)])

        var pids: [pid_t] = []
        while pids.isEmpty {
            pids = await core.workerPIDs
            try await Task.sleep(for: .milliseconds(20))
        }
        await core.shutdown()

        for pid in pids { #expect(gone(pid), "worker \(pid) outlived shutdown") }
        #expect(await core.workerPIDs.isEmpty)
        let snapshot = await core.snapshot()
        #expect(snapshot.running == 0 && snapshot.queued == 0)
        #expect(snapshot.jobs.allSatisfy { $0.status == .interrupted }, "in-flight work is interrupted, never shown as running")
        let refused = try await call(core, "alethe_delegate", ["tasks": ["late"], "cwd": .string(folder.path)])
        #expect(refused["error"] != nil, "no work starts after shutdown")
    }

    @Test func cancellingARunningWorkerEndsItsProcessAndAnnouncesIt() async throws {
        let folder = try temporaryDirectory("cancel")
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore([silentLauncher()])
        _ = try await call(core, "alethe_delegate", ["tasks": ["one"], "cwd": .string(folder.path)])
        var pids: [pid_t] = []
        while pids.isEmpty {
            pids = await core.workerPIDs
            try await Task.sleep(for: .milliseconds(20))
        }

        let cancelled = try await call(core, "alethe_cancel", ["jobIds": ["job-01", "job-99"]])
        #expect(cancelled["cancelled"] == ["job-01"])
        let checked = try await call(core, "alethe_check", ["wait": true, "timeoutMs": 5000])
        #expect(deliveries(checked).first?["outcome"] == "cancelled")
        await core.shutdown()
        for pid in pids { #expect(gone(pid)) }
    }

    @Test func releasingAQueuedJobFreesItsPlaceWithoutStartingIt() async throws {
        let folder = try temporaryDirectory("release")
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore([silentLauncher()], limit: 1)
        _ = try await call(core, "alethe_delegate", ["tasks": ["one", "two"], "cwd": .string(folder.path)])

        let released = try await call(core, "alethe_release", ["jobIds": ["job-01", "job-02"]])
        #expect(released["released"] == ["job-02"], "a running job is not released")
        let counts = await core.counts()
        #expect(counts.running == 1 && counts.queued == 0)
        await core.shutdown()
    }

    @Test func theConcurrencyLimitIsClamped() async {
        let core = makeCore(limit: 0)
        #expect(await core.snapshot().concurrencyLimit == 1)
        await core.setConcurrencyLimit(99)
        #expect(await core.snapshot().concurrencyLimit == 16)
    }

    @Test func delegateArgumentsReadLikeUpstream() throws {
        let request = try DelegateRequest(arguments: [
            "tasks": ["a", 1, "b"], "cwd": "/tmp", "label": "  ", "agent": "", "timeoutSeconds": 0,
        ])
        #expect(request.tasks == ["a", "b"])
        #expect(request.agent == WorkerAgent.codex)
        #expect(request.label == nil)
        #expect(request.timeoutMs == nil, "0 runs without a budget")
        let defaults = try DelegateRequest(arguments: ["tasks": ["a"], "cwd": "/tmp"])
        #expect(defaults.timeoutMs == OrchestratorLimits.defaultJobTimeoutMs)
    }
}
