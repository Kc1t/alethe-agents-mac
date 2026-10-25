import Darwin
import Foundation

public struct ProcessStartTime: Hashable, Sendable, Codable {
    public var seconds: Int64
    public var microseconds: Int32

    public init(seconds: Int64, microseconds: Int32) {
        self.seconds = seconds
        self.microseconds = microseconds
    }
}

public struct LiveProcess: Hashable, Sendable {
    public var pid: pid_t
    public var groupID: pid_t
    public var startTime: ProcessStartTime
    public var executable: String?

    public init(pid: pid_t, groupID: pid_t, startTime: ProcessStartTime, executable: String?) {
        self.pid = pid
        self.groupID = groupID
        self.startTime = startTime
        self.executable = executable
    }
}

enum WorkerProcessTable {
    static func process(_ pid: pid_t) -> LiveProcess? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else {
            return nil
        }
        let start = info.kp_proc.p_starttime
        return LiveProcess(pid: pid, groupID: info.kp_eproc.e_pgid,
                           startTime: ProcessStartTime(seconds: Int64(start.tv_sec), microseconds: start.tv_usec),
                           executable: executable(of: pid))
    }

    static func executable(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func parents() -> [pid_t: pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [:] }
        size += size / 8
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return [:] }
        var parents: [pid_t: pid_t] = [:]
        for proc in procs.prefix(size / MemoryLayout<kinfo_proc>.stride) {
            parents[proc.kp_proc.p_pid] = proc.kp_eproc.e_ppid
        }
        return parents
    }

    static func descendants(of root: pid_t, parents: [pid_t: pid_t]) -> [pid_t] {
        var children: [pid_t: [pid_t]] = [:]
        for (pid, parent) in parents where pid != parent { children[parent, default: []].append(pid) }
        var result: [pid_t] = []
        var queue = [root]
        var seen: Set<pid_t> = []
        while !queue.isEmpty {
            let pid = queue.removeFirst()
            guard seen.insert(pid).inserted else { continue }
            result.append(pid)
            queue.append(contentsOf: (children[pid] ?? []).sorted())
        }
        return result
    }

    static func killTree(leader: pid_t, leaderAlive: Bool) {
        let tree = descendants(of: leader, parents: parents())
        for member in tree.reversed() where member != leader || leaderAlive {
            Darwin.kill(member, SIGKILL)
        }
        Darwin.kill(-leader, SIGKILL)
    }

    static func bootTime() -> ProcessStartTime? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, UInt32(mib.count), &boot, &size, nil, 0) == 0 else { return nil }
        return ProcessStartTime(seconds: Int64(boot.tv_sec), microseconds: boot.tv_usec)
    }
}
