import Foundation

public enum RemoteText {
    public static func tokensEqual(_ provided: String, _ expected: String) -> Bool {
        let lhs = Array(provided.utf8)
        let rhs = Array(expected.utf8)
        var difference = lhs.count ^ rhs.count
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            difference |= Int(left ^ right)
        }
        return difference == 0
    }

    public static func sanitize(_ input: String) -> String {
        var output = String.UnicodeScalarView()
        for scalar in input.unicodeScalars {
            output.append(scalar.properties.generalCategory == .control ? " " : scalar)
        }
        return String(output)
    }

    public static func queryValue(_ target: String, _ key: String) -> String? {
        let parts = target.split(separator: "?", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count > 1 else { return nil }
        for pair in parts[1].split(separator: "&", omittingEmptySubsequences: false) {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            if pair[..<equals] == key[...] {
                return percentDecode(String(pair[pair.index(after: equals)...]))
            }
        }
        return nil
    }

    public static func percentDecode(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "%"), index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) {
                decoded.append(high << 4 | low)
                index += 3
            } else if byte == UInt8(ascii: "+") {
                decoded.append(UInt8(ascii: " "))
                index += 1
            } else {
                decoded.append(byte)
                index += 1
            }
        }
        return String(decoding: decoded, as: UTF8.self)
    }

    public static func truncated(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) : text
    }

    public static func randomToken(length: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        var scalars = String.UnicodeScalarView()
        for _ in 0..<length {
            let index = Int(UInt8.random(in: 0...255, using: &generator) & 63)
            scalars.append(tokenAlphabet[index])
        }
        return String(scalars)
    }

    private static let tokenAlphabet = Array("useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict".unicodeScalars)

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        if (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) { return byte - UInt8(ascii: "0") }
        if (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte) { return byte - UInt8(ascii: "a") + 10 }
        if (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte) { return byte - UInt8(ascii: "A") + 10 }
        return nil
    }
}
