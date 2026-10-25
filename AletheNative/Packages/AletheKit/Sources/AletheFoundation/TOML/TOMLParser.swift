import Foundation

struct TOMLSyntaxError: Error {
    let offset: Int
    let reason: String
}

struct TOMLIndex: Sendable {
    enum TriviaKind: Sendable { case blank, comment }

    struct Trivia: Sendable {
        let start: Int
        let kind: TriviaKind
    }

    struct Statement: Sendable {
        let key: [String]
        let line: Range<Int>
        let valueRange: Range<Int>
        let value: TOMLValue
    }

    struct Section: Sendable {
        let path: [String]
        let isArray: Bool
        let isArrayScoped: Bool
        let header: Range<Int>?
        var statements: [Statement] = []
        var bodyEnd: Int

        var isRoot: Bool { header == nil }
    }

    var sections: [Section]
    var trivia: [Int: Trivia]
    var root: TOMLTable
    var newline: String
    var contentStart: Int
}

enum TOMLStep: Hashable, Sendable {
    case key(String)
    case index(Int)
}

struct TOMLParser {
    let bytes: [UInt8]
    var i = 0
    private var builder = TOMLTreeBuilder()
    private static let maxDepth = 100

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    static func parse(_ bytes: [UInt8]) throws -> TOMLIndex {
        var parser = TOMLParser(bytes: bytes)
        return try parser.run()
    }

    private mutating func run() throws -> TOMLIndex {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { i = 3 }
        let contentStart = i
        var sections = [TOMLIndex.Section(path: [], isArray: false, isArrayScoped: false, header: nil,
                                          bodyEnd: contentStart)]
        var trivia: [Int: TOMLIndex.Trivia] = [:]

        while i < bytes.count {
            let lineStart = i
            skipSpaces()
            if atLineEnd {
                consumeLineEnd()
                trivia[i] = .init(start: lineStart, kind: .blank)
                continue
            }
            if bytes[i] == ascii("#") {
                try skipComment()
                try finishLine()
                trivia[i] = .init(start: lineStart, kind: .comment)
                continue
            }
            if bytes[i] == ascii("[") {
                let isArray = peek(1) == ascii("[")
                i += isArray ? 2 : 1
                let path = try parseKey()
                try expect("]")
                if isArray { try expect("]") }
                try finishLine()
                do {
                    try builder.openTable(path, isArray: isArray)
                } catch let failure as BuildFailure {
                    throw TOMLSyntaxError(offset: lineStart, reason: failure.reason)
                }
                sections.append(.init(path: path, isArray: isArray, isArrayScoped: builder.currentIsArrayScoped,
                                      header: lineStart..<i, bodyEnd: i))
                continue
            }
            let key = try parseKey()
            try expect("=")
            skipSpaces()
            let valueStart = i
            let value = try parseValue(depth: 0)
            let valueEnd = i
            try finishLine()
            do {
                try builder.insert(key, value)
            } catch let failure as BuildFailure {
                throw TOMLSyntaxError(offset: lineStart, reason: failure.reason)
            }
            sections[sections.count - 1].statements.append(
                .init(key: key, line: lineStart..<i, valueRange: valueStart..<valueEnd, value: value))
            sections[sections.count - 1].bodyEnd = i
        }

        return TOMLIndex(sections: sections, trivia: trivia, root: builder.root, newline: detectNewline(),
                         contentStart: contentStart)
    }

    private func detectNewline() -> String {
        if let newline = bytes.firstIndex(of: 0x0A), newline > 0, bytes[newline - 1] == 0x0D { return "\r\n" }
        return "\n"
    }

    func ascii(_ character: Unicode.Scalar) -> UInt8 { UInt8(ascii: character) }

    func peek(_ offset: Int) -> UInt8? {
        i + offset < bytes.count ? bytes[i + offset] : nil
    }

    private var atLineEnd: Bool {
        i == bytes.count || bytes[i] == 0x0A || (bytes[i] == 0x0D && peek(1) == 0x0A)
    }

    private mutating func consumeLineEnd() {
        guard i < bytes.count else { return }
        i += bytes[i] == 0x0D ? 2 : 1
    }

    mutating func skipSpaces() {
        while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x09 { i += 1 }
    }

    static func isControl(_ byte: UInt8) -> Bool {
        (byte < 0x20 && byte != 0x09) || byte == 0x7F
    }

    static func isDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
    }

    private mutating func skipComment() throws {
        i += 1
        while i < bytes.count {
            let byte = bytes[i]
            if byte == 0x0A || (byte == 0x0D && peek(1) == 0x0A) { return }
            if Self.isControl(byte) { throw TOMLSyntaxError(offset: i, reason: "control character in a comment") }
            i += 1
        }
    }

    private mutating func finishLine() throws {
        skipSpaces()
        if i < bytes.count, bytes[i] == ascii("#") { try skipComment() }
        guard atLineEnd else { throw TOMLSyntaxError(offset: i, reason: "expected the end of the line") }
        consumeLineEnd()
    }

    mutating func skipBlank() throws {
        while true {
            skipSpaces()
            if i < bytes.count, bytes[i] == ascii("#") { try skipComment() }
            if i < bytes.count, bytes[i] == 0x0A {
                i += 1
            } else if i < bytes.count, bytes[i] == 0x0D, peek(1) == 0x0A {
                i += 2
            } else {
                return
            }
        }
    }

    mutating func expect(_ character: Unicode.Scalar) throws {
        guard i < bytes.count, bytes[i] == ascii(character) else {
            throw TOMLSyntaxError(offset: i, reason: "expected '\(character)'")
        }
        i += 1
    }

    private func hasPrefix(_ text: String) -> Bool {
        let prefix = Array(text.utf8)
        return i + prefix.count <= bytes.count && Array(bytes[i..<(i + prefix.count)]) == prefix
    }

    mutating func parseKey() throws -> [String] {
        var parts: [String] = []
        while true {
            skipSpaces()
            parts.append(try parseSimpleKey())
            skipSpaces()
            guard i < bytes.count, bytes[i] == ascii(".") else { return parts }
            i += 1
        }
    }

    private mutating func parseSimpleKey() throws -> String {
        guard i < bytes.count else { throw TOMLSyntaxError(offset: i, reason: "expected a key") }
        if hasPrefix("\"\"\"") || hasPrefix("'''") {
            throw TOMLSyntaxError(offset: i, reason: "a key cannot be a multi-line string")
        }
        if bytes[i] == ascii("\"") { return try parseBasicString() }
        if bytes[i] == ascii("'") { return try parseLiteralString() }
        let start = i
        while i < bytes.count {
            let byte = bytes[i]
            let bare = Self.isDigit(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                || byte == ascii("_") || byte == ascii("-")
            guard bare else { break }
            i += 1
        }
        guard i > start else { throw TOMLSyntaxError(offset: i, reason: "expected a key") }
        return String(decoding: bytes[start..<i], as: UTF8.self)
    }

    mutating func parseValue(depth: Int) throws -> TOMLValue {
        guard depth < Self.maxDepth else { throw TOMLSyntaxError(offset: i, reason: "values are nested too deeply") }
        guard i < bytes.count else { throw TOMLSyntaxError(offset: i, reason: "expected a value") }
        if bytes[i] == ascii("\"") {
            return .string(hasPrefix("\"\"\"") ? try parseMultilineBasicString() : try parseBasicString())
        } else if bytes[i] == ascii("'") {
            return .string(hasPrefix("'''") ? try parseMultilineLiteralString() : try parseLiteralString())
        } else if bytes[i] == ascii("[") {
            return try parseArray(depth: depth)
        } else if bytes[i] == ascii("{") {
            return try parseInlineTable(depth: depth)
        } else {
            return try parseScalarToken()
        }
    }
}
