import Foundation

public final class ScrollbackFile: @unchecked Sendable {
    public static let cap = 4 * 1024 * 1024
    public static let flushInterval: Duration = .milliseconds(250)

    public let url: URL
    private let cap: Int
    private let flushInterval: Duration
    private let queue = DispatchQueue(label: "alethe.scrollback", qos: .utility)
    private var pending = Data()
    private var flushScheduled = false

    public init(url: URL, cap: Int = ScrollbackFile.cap, flushInterval: Duration = ScrollbackFile.flushInterval) {
        precondition(cap > 0 && cap <= Int.max / 2)
        self.url = url
        self.cap = cap
        self.flushInterval = flushInterval
    }

    public func load() -> Data {
        queue.sync {
            guard let data = try? Data(contentsOf: url) else { return Data() }
            return Self.safeTail(data, capacity: cap)
        }
    }

    public func append(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.async { [self] in
            pending.append(data)
            if pending.count > cap * 2 { pending = Self.safeTail(pending, capacity: cap) }
            guard !flushScheduled else { return }
            flushScheduled = true
            queue.asyncAfter(deadline: .now() + flushInterval.timeInterval) { [self] in writePending() }
        }
    }

    public func flush() {
        queue.sync { writePending() }
    }

    public func clear() {
        queue.async { [self] in
            pending.removeAll()
            try? Data().write(to: url, options: .atomic)
        }
    }

    public func delete() {
        queue.async { [self] in
            pending.removeAll()
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func writePending() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let bytes = pending
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return }
        do {
            try handle.write(contentsOf: bytes)
            try handle.synchronize()
        } catch {
            try? handle.truncate(atOffset: end)
            return
        }
        pending.removeFirst(bytes.count)
        if end + UInt64(bytes.count) > UInt64(cap * 2) { compact() }
    }

    private func compact() {
        guard let data = try? Data(contentsOf: url), data.count > cap else { return }
        try? Self.safeTail(data, capacity: cap).write(to: url, options: .atomic)
    }

    public static func safeTail(_ data: Data, capacity: Int) -> Data {
        precondition(capacity > 0)
        guard data.count > capacity else { return data }
        let bytes = Array(data)
        let cutoff = bytes.count - capacity
        var state = 0
        var osc = false
        for index in bytes.indices {
            let byte = bytes[index]
            if index >= cutoff, state == 0, byte & 0xc0 != 0x80 {
                return Data(bytes[index...])
            }
            advance(byte, state: &state, osc: &osc)
        }
        return Data()
    }

    private static func advance(_ byte: UInt8, state: inout Int, osc: inout Bool) {
        switch state {
        case 0:
            if byte == 0x1b { state = 1 }
        case 1:
            switch byte {
            case 0x5b: state = 2
            case 0x5d: state = 3; osc = true
            case 0x50, 0x58, 0x5e, 0x5f: state = 3; osc = false
            case 0x20...0x2f: break
            default: state = 0
            }
        case 2:
            if (0x40...0x7e).contains(byte) { state = 0 }
            else if byte == 0x1b { state = 1 }
        case 3:
            if osc && byte == 0x07 { state = 0 }
            else if byte == 0x1b { state = 4 }
        default:
            if byte == 0x5c { state = 0 }
            else if byte != 0x1b { state = 3 }
        }
        if byte == 0x18 || byte == 0x1a { state = 0 }
    }

    private static func completeReplay(_ data: Data) -> Data {
        var state = 0
        var osc = false
        var sequenceStart = data.startIndex
        for index in data.indices {
            if state == 0 { sequenceStart = index }
            advance(data[index], state: &state, osc: &osc)
        }
        return state == 0 ? data : Data(data[..<sequenceStart])
    }

    public static func withoutQueries(_ data: Data) -> Data {
        guard let text = String(data: completeReplay(data), encoding: .isoLatin1) else { return data }
        let stripped = text.replacingOccurrences(of: queryPattern, with: "", options: .regularExpression)
        return stripped.data(using: .isoLatin1) ?? data
    }

    static let queryPattern = [
        #"\x{1B}\[[>=]?[0-9;]*c"#,
        #"\x{1B}\[>[0-9;]*q"#,
        #"\x{1B}\[\?u"#,
        #"\x{1B}\[\??[0-9;]*\$p"#,
        #"\x{1B}\[\??[0-9;]*n"#,
        #"\x{1B}\[(?:11|13|14|15|16|18|19|20|21)(?:;[0-9]*)*t"#,
        #"\x{1B}\][0-9;]*;\?(?:\x{07}|\x{1B}\\)"#,
        #"\x{1B}P[$+]q[^\x{1B}]*\x{1B}\\"#,
        #"\x{1B}_G[^\x{1B}]*\x{1B}\\"#,
    ].joined(separator: "|")

    public static let replayReset = Data((
        "\u{1b}[?1049l\u{1b}[?1000l\u{1b}[?1002l\u{1b}[?1003l\u{1b}[?1006l\u{1b}[?2004l"
            + "\u{1b}[?1004l\u{1b}[?1l\u{1b}>\u{1b}[<99u\u{1b}[=0;1u\u{1b}[>4;0m"
            + "\u{1b}[?25h\u{1b}[0m\u{1b}[22J\u{1b}[H").utf8)
}

extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
