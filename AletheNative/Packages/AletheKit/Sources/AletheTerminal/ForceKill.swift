import Darwin
import Foundation

public struct DoubleInterrupt: Sendable {
    public static let window: Duration = .milliseconds(1500)

    private var last: ContinuousClock.Instant?

    public init() {}

    public mutating func register(_ input: Data, at now: ContinuousClock.Instant) -> Bool {
        guard Self.isInterrupt(input) else {
            last = nil
            return false
        }
        if let last, last.duration(to: now) < Self.window {
            self.last = nil
            return true
        }
        last = now
        return false
    }

    public static func isInterrupt(_ input: Data) -> Bool {
        if input == Data([0x03]) { return true }
        guard let text = String(data: input, encoding: .utf8) else { return false }
        return text == "\u{1b}[99;5u" || text == "\u{1b}[99;5:1u"
    }
}

public enum ProcessTree {
    public static func descendants(of root: pid_t, parents: [pid_t: pid_t]) -> [pid_t] {
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

    public static func currentParents() -> [pid_t: pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [:] }
        size += size / 8
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return [:] }
        var parents: [pid_t: pid_t] = [:]
        for proc in procs.prefix(size / MemoryLayout<kinfo_proc>.stride) {
            parents[proc.kp_proc.p_pid] = proc.kp_eproc.e_ppid
        }
        return parents
    }

    public static func kill(_ root: pid_t) {
        guard root > 0 else { return }
        for pid in descendants(of: root, parents: currentParents()).reversed() {
            Darwin.kill(pid, SIGKILL)
        }
        Darwin.kill(-root, SIGKILL)
    }
}
