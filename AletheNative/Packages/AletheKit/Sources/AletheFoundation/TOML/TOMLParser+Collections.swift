import Foundation

extension TOMLParser {
    mutating func parseArray(depth: Int) throws -> TOMLValue {
        let start = i
        i += 1
        var items: [TOMLValue] = []
        while true {
            try skipBlank()
            guard i < bytes.count else { throw TOMLSyntaxError(offset: start, reason: "unterminated array") }
            if bytes[i] == ascii("]") {
                i += 1
                return .array(items)
            }
            items.append(try parseValue(depth: depth + 1))
            try skipBlank()
            guard i < bytes.count else { throw TOMLSyntaxError(offset: start, reason: "unterminated array") }
            if bytes[i] == ascii(",") {
                i += 1
                continue
            }
            if bytes[i] == ascii("]") {
                i += 1
                return .array(items)
            }
            throw TOMLSyntaxError(offset: i, reason: "expected ',' or ']'")
        }
    }

    mutating func parseInlineTable(depth: Int) throws -> TOMLValue {
        let start = i
        i += 1
        var table = TOMLTable(style: .inline)
        var created = Set<[String]>()
        try skipBlank()
        if i < bytes.count, bytes[i] == ascii("}") {
            i += 1
            return .table(table)
        }
        while true {
            try skipBlank()
            let keyStart = i
            let key = try parseKey()
            try expect("=")
            skipSpaces()
            let value = try parseValue(depth: depth + 1)
            guard Self.insertInline(value, at: key, into: &table, created: &created) else {
                throw TOMLSyntaxError(offset: keyStart, reason: "a key is defined twice")
            }
            try skipBlank()
            guard i < bytes.count else { throw TOMLSyntaxError(offset: start, reason: "unterminated inline table") }
            if bytes[i] == ascii(",") {
                i += 1
                try skipBlank()
                if i < bytes.count, bytes[i] == ascii("}") {
                    i += 1
                    return .table(table)
                }
                continue
            }
            if bytes[i] == ascii("}") {
                i += 1
                return .table(table)
            }
            throw TOMLSyntaxError(offset: i, reason: "expected ',' or '}'")
        }
    }

    private static func insertInline(_ value: TOMLValue, at key: [String], into table: inout TOMLTable,
                                     created: inout Set<[String]>) -> Bool {
        for length in 1..<max(key.count, 1) {
            let prefix = Array(key[..<length])
            let existing = table.value(at: prefix)
            if existing == nil {
                table.setValue(.table(TOMLTable(style: .inline)), at: prefix[...], intermediateStyle: .inline)
                created.insert(prefix)
            } else if case .some(.table) = existing, created.contains(prefix) {
                continue
            } else {
                return false
            }
        }
        guard table.value(at: key) == nil else { return false }
        return table.setValue(value, at: key[...], intermediateStyle: .inline)
    }
}
