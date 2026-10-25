import Foundation

extension TOMLParser {
    mutating func parseBasicString() throws -> String {
        let start = i
        i += 1
        var out: [UInt8] = []
        while true {
            guard i < bytes.count else { throw TOMLSyntaxError(offset: start, reason: "unterminated string") }
            let byte = bytes[i]
            if byte == ascii("\"") {
                i += 1
                return String(decoding: out, as: UTF8.self)
            }
            if byte == ascii("\\") {
                try parseEscape(into: &out)
                continue
            }
            if byte == 0x0A || byte == 0x0D { throw TOMLSyntaxError(offset: start, reason: "unterminated string") }
            if Self.isControl(byte) { throw TOMLSyntaxError(offset: i, reason: "control character in a string") }
            out.append(byte)
            i += 1
        }
    }

    private static let escapedBytes: [UInt8: UInt8] = [
        UInt8(ascii: "b"): 0x08, UInt8(ascii: "t"): 0x09, UInt8(ascii: "n"): 0x0A,
        UInt8(ascii: "f"): 0x0C, UInt8(ascii: "r"): 0x0D, UInt8(ascii: "e"): 0x1B,
        UInt8(ascii: "\""): UInt8(ascii: "\""), UInt8(ascii: "\\"): UInt8(ascii: "\\"),
    ]

    private static let escapeHexDigits: [UInt8: Int] = [
        UInt8(ascii: "x"): 2, UInt8(ascii: "u"): 4, UInt8(ascii: "U"): 8,
    ]

    private mutating func parseEscape(into out: inout [UInt8]) throws {
        let start = i
        i += 1
        guard i < bytes.count else { throw TOMLSyntaxError(offset: start, reason: "invalid escape sequence") }
        let byte = bytes[i]
        i += 1
        if let escaped = Self.escapedBytes[byte] {
            out.append(escaped)
            return
        }
        guard let count = Self.escapeHexDigits[byte] else {
            throw TOMLSyntaxError(offset: start, reason: "invalid escape sequence")
        }
        try appendScalar(hexDigits: count, into: &out, escapeStart: start)
    }

    private mutating func appendScalar(hexDigits count: Int, into out: inout [UInt8], escapeStart: Int) throws {
        guard i + count <= bytes.count,
              let value = UInt32(String(decoding: bytes[i..<(i + count)], as: UTF8.self), radix: 16),
              bytes[i..<(i + count)].allSatisfy({ $0 != ascii("+") && $0 != ascii("-") }),
              let scalar = Unicode.Scalar(value) else {
            throw TOMLSyntaxError(offset: escapeStart, reason: "invalid unicode escape")
        }
        i += count
        out.append(contentsOf: Array(String(Character(scalar)).utf8))
    }

    private mutating func skipOneNewline() {
        if i < bytes.count, bytes[i] == 0x0A {
            i += 1
        } else if i < bytes.count, bytes[i] == 0x0D, peek(1) == 0x0A {
            i += 2
        }
    }

    private mutating func closingQuotes(_ quote: UInt8, into out: inout [UInt8]) throws -> Bool {
        var run = 0
        while i + run < bytes.count, bytes[i + run] == quote { run += 1 }
        if run >= 3 {
            guard run <= 5 else { throw TOMLSyntaxError(offset: i, reason: "too many quotes") }
            out.append(contentsOf: repeatElement(quote, count: run - 3))
            i += run
            return true
        }
        out.append(contentsOf: repeatElement(quote, count: run))
        i += run
        return false
    }

    mutating func parseMultilineBasicString() throws -> String {
        let start = i
        i += 3
        skipOneNewline()
        var out: [UInt8] = []
        while true {
            guard i < bytes.count else { throw TOMLSyntaxError(offset: start, reason: "unterminated string") }
            let byte = bytes[i]
            if byte == ascii("\"") {
                if try closingQuotes(byte, into: &out) { return String(decoding: out, as: UTF8.self) }
                continue
            }
            if byte == ascii("\\") {
                var next = i + 1
                while next < bytes.count, bytes[next] == 0x20 || bytes[next] == 0x09 { next += 1 }
                let endsLine = next < bytes.count
                    && (bytes[next] == 0x0A || (bytes[next] == 0x0D && next + 1 < bytes.count && bytes[next + 1] == 0x0A))
                if endsLine {
                    i = next
                    while i < bytes.count {
                        if bytes[i] == 0x20 || bytes[i] == 0x09 || bytes[i] == 0x0A {
                            i += 1
                        } else if bytes[i] == 0x0D, peek(1) == 0x0A {
                            i += 2
                        } else {
                            break
                        }
                    }
                    continue
                }
                try parseEscape(into: &out)
                continue
            }
            try appendMultilineByte(byte, into: &out)
        }
    }

    private mutating func appendMultilineByte(_ byte: UInt8, into out: inout [UInt8]) throws {
        if byte == 0x0D {
            guard peek(1) == 0x0A else { throw TOMLSyntaxError(offset: i, reason: "control character in a string") }
            out.append(0x0A)
            i += 2
            return
        }
        if byte != 0x0A, Self.isControl(byte) {
            throw TOMLSyntaxError(offset: i, reason: "control character in a string")
        }
        out.append(byte)
        i += 1
    }

    mutating func parseLiteralString() throws -> String {
        let start = i
        i += 1
        let contentStart = i
        while true {
            guard i < bytes.count else { throw TOMLSyntaxError(offset: start, reason: "unterminated string") }
            let byte = bytes[i]
            if byte == ascii("'") {
                let text = String(decoding: bytes[contentStart..<i], as: UTF8.self)
                i += 1
                return text
            }
            if byte == 0x0A || byte == 0x0D { throw TOMLSyntaxError(offset: start, reason: "unterminated string") }
            if Self.isControl(byte) { throw TOMLSyntaxError(offset: i, reason: "control character in a string") }
            i += 1
        }
    }

    mutating func parseMultilineLiteralString() throws -> String {
        let start = i
        i += 3
        skipOneNewline()
        var out: [UInt8] = []
        while true {
            guard i < bytes.count else { throw TOMLSyntaxError(offset: start, reason: "unterminated string") }
            let byte = bytes[i]
            if byte == ascii("'") {
                if try closingQuotes(byte, into: &out) { return String(decoding: out, as: UTF8.self) }
                continue
            }
            try appendMultilineByte(byte, into: &out)
        }
    }
}
