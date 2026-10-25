import Darwin
import Foundation

public struct ProcessNode: Equatable, Sendable, Identifiable {
    public let pid: pid_t
    public let parentPID: pid_t
    public let name: String
    public let command: String
    public let memoryMB: Double
    public let ports: [UInt16]
    public var id: pid_t { pid }

    public init(pid: pid_t, parentPID: pid_t, name: String, command: String, memoryMB: Double, ports: [UInt16]) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.command = command
        self.memoryMB = memoryMB
        self.ports = ports
    }
}

public enum ProcessInspector {
    public static func children(of root: pid_t, parents: [pid_t: pid_t]) -> [ProcessNode] {
        guard root > 0 else { return [] }
        return ProcessTree.descendants(of: root, parents: parents).dropFirst().map { pid in
            ProcessNode(pid: pid, parentPID: parents[pid] ?? root, name: name(of: pid),
                        command: command(of: pid), memoryMB: SystemResources.footprintMB(of: pid),
                        ports: listeningPorts(of: pid))
        }
    }

    public static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : ""
    }

    public static func command(of pid: pid_t) -> String {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return "" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return "" }
        return parseCommand(Array(buffer.prefix(size)))
    }

    static func parseCommand(_ bytes: [UInt8]) -> String {
        let countSize = MemoryLayout<Int32>.size
        guard bytes.count > countSize else { return "" }
        let argc = bytes.prefix(countSize).withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = countSize
        func next() -> String? {
            guard index < bytes.count else { return nil }
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            defer { index += 1 }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }
        guard let executable = next(), !executable.isEmpty else { return "" }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, let argument = next() { arguments.append(argument) }
        let program = (executable as NSString).lastPathComponent
        return ([program] + arguments.dropFirst()).joined(separator: " ")
    }

    public static func listeningPorts(of pid: pid_t) -> [UInt16] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        let capacity = Int(bytes) / MemoryLayout<proc_fdinfo>.stride + 16
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, Int32(capacity * MemoryLayout<proc_fdinfo>.stride))
        guard filled > 0 else { return [] }
        var ports: Set<UInt16> = []
        for descriptor in descriptors.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let read = proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info,
                                      Int32(MemoryLayout<socket_fdinfo>.stride))
            guard read == Int32(MemoryLayout<socket_fdinfo>.stride),
                  info.psi.soi_kind == Int32(SOCKINFO_TCP),
                  info.psi.soi_proto.pri_tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { continue }
            let port = UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)
            ports.insert(UInt16(bigEndian: port))
        }
        return ports.sorted()
    }
}
