import AletheFoundation
import Darwin
import Foundation
import Synchronization

public struct WorkerRecord: Hashable, Sendable, Codable {
    public var pid: pid_t
    public var groupID: pid_t
    public var executables: [String]
    public var startTime: ProcessStartTime
    public var jobID: String?

    public init(pid: pid_t, groupID: pid_t, executables: [String], startTime: ProcessStartTime, jobID: String?) {
        self.pid = pid
        self.groupID = groupID
        self.executables = executables
        self.startTime = startTime
        self.jobID = jobID
    }
}

public final class WorkerRegistry: Sendable {
    public static let fileName = "orchestrator-workers.json"

    private struct Document: Codable {
        var version = 1
        var bootTime: ProcessStartTime?
        var workers: [WorkerRecord] = []
    }

    public let url: URL
    private let state = Mutex<[WorkerRecord]>([])

    public init(url: URL) {
        self.url = url
    }

    public convenience init(profileDirectory: URL) {
        self.init(url: profileDirectory.appending(path: Self.fileName))
    }

    public var records: [WorkerRecord] { state.withLock { $0 } }

    public static var currentBootTime: ProcessStartTime? { WorkerProcessTable.bootTime() }

    public func add(_ record: WorkerRecord) {
        state.withLock { records in
            records.removeAll { $0.pid == record.pid }
            records.append(record)
            write(records)
        }
    }

    public func noteExecutable(_ executable: String, for pid: pid_t) {
        state.withLock { records in
            guard let index = records.firstIndex(where: { $0.pid == pid }),
                  !records[index].executables.contains(executable) else { return }
            records[index].executables.append(executable)
            write(records)
        }
    }

    public func remove(pid: pid_t) {
        state.withLock { records in
            let before = records.count
            records.removeAll { $0.pid == pid }
            if records.count != before { write(records) }
        }
    }

    public static func matches(_ record: WorkerRecord, live: LiveProcess?) -> Bool {
        guard let live, live.pid == record.pid, live.startTime == record.startTime,
              let executable = live.executable else { return false }
        return record.executables.contains(executable)
    }

    public func leftovers(currentBoot: ProcessStartTime? = WorkerRegistry.currentBootTime) -> [WorkerRecord] {
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Document.self, from: data) else { return [] }
        guard document.bootTime == nil || currentBoot == nil || document.bootTime == currentBoot else { return [] }
        return document.workers
    }

    @concurrent
    public func terminateLeftovers(
        grace: Duration = WorkerProcess.terminationGrace,
        lookup: (@Sendable (pid_t) -> LiveProcess?)? = nil
    ) async -> [pid_t] {
        let lookup = lookup ?? { WorkerProcessTable.process($0) }
        let own = getpid()
        let current = Set(records.map(\.pid))
        let stale = leftovers().filter { record in
            !current.contains(record.pid) && record.pid != own && record.pid > 1
                && Self.matches(record, live: lookup(record.pid))
        }
        for record in stale {
            Darwin.kill(-record.groupID, SIGTERM)
            Darwin.kill(record.pid, SIGTERM)
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: grace)
        while stale.contains(where: { Self.matches($0, live: lookup($0.pid)) }), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        for record in stale {
            WorkerProcessTable.killTree(leader: record.pid, leaderAlive: Self.matches(record, live: lookup(record.pid)))
        }
        if !stale.isEmpty {
            AppLog.record(.warning, .orchestrator, "Ended \(stale.count) worker(s) left by an earlier run")
        }
        state.withLock { write($0) }
        return stale.map(\.pid)
    }

    private func write(_ records: [WorkerRecord]) {
        let document = Document(bootTime: WorkerProcessTable.bootTime(), workers: records)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(document).write(to: url, options: .atomic)
        } catch {
            AppLog.record(.warning, .orchestrator, "Could not record live workers: \(error)")
        }
    }
}
