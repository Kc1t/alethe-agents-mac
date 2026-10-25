import Foundation

extension TOMLParser {
    mutating func parseScalarToken() throws -> TOMLValue {
        let start = i
        func isTokenByte(_ byte: UInt8) -> Bool {
            Self.isDigit(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-")
                || byte == UInt8(ascii: ".") || byte == UInt8(ascii: ":")
        }
        while i < bytes.count, isTokenByte(bytes[i]) { i += 1 }
        if i - start == 10, i + 3 < bytes.count, bytes[start + 4] == ascii("-"), bytes[start + 7] == ascii("-"),
           bytes[i] == 0x20, Self.isDigit(bytes[i + 1]), Self.isDigit(bytes[i + 2]), bytes[i + 3] == ascii(":") {
            i += 1
            while i < bytes.count, isTokenByte(bytes[i]) { i += 1 }
        }
        guard i > start else { throw TOMLSyntaxError(offset: start, reason: "expected a value") }
        let token = Array(bytes[start..<i])
        let text = String(decoding: token, as: UTF8.self)
        if let value = Self.scalarValues[text] { return value }
        if Self.looksLikeDateTime(token) { return .datetime(text) }
        if let number = Self.number(token) { return number }
        throw TOMLSyntaxError(offset: start, reason: "invalid value")
    }

    private static let scalarValues: [String: TOMLValue] = [
        "true": .boolean(true), "false": .boolean(false),
        "inf": .float(.infinity), "+inf": .float(.infinity), "-inf": .float(-.infinity),
        "nan": .float(.nan), "+nan": .float(.nan), "-nan": .float(.nan),
    ]

    private static func looksLikeDateTime(_ token: [UInt8]) -> Bool {
        let date = token.count >= 10 && token[0..<4].allSatisfy(isDigit) && token[4] == UInt8(ascii: "-")
        let time = token.count >= 8 && token[0..<2].allSatisfy(isDigit) && token[2] == UInt8(ascii: ":")
        guard date || time else { return false }
        let allowed = Set("0123456789-:.+TtZz ".utf8)
        return token.allSatisfy { allowed.contains($0) }
    }

    private static func validDigits(_ digits: ArraySlice<UInt8>, _ isValid: (UInt8) -> Bool) -> Bool {
        guard let first = digits.first, let last = digits.last, first != UInt8(ascii: "_"),
              last != UInt8(ascii: "_") else { return false }
        var previousUnderscore = false
        for byte in digits {
            if byte == UInt8(ascii: "_") {
                if previousUnderscore { return false }
                previousUnderscore = true
            } else {
                guard isValid(byte) else { return false }
                previousUnderscore = false
            }
        }
        return true
    }

    private static let radices: [UInt8: Int] = [UInt8(ascii: "x"): 16, UInt8(ascii: "o"): 8, UInt8(ascii: "b"): 2]

    private static func number(_ token: [UInt8]) -> TOMLValue? {
        if token.count > 2, token[0] == UInt8(ascii: "0"), let radix = radices[token[1]] {
            return radixNumber(token, radix: radix)
        }
        return decimalNumber(token)
    }

    private static func radixNumber(_ token: [UInt8], radix: Int) -> TOMLValue? {
        let digits = token[2...]
        let valid = validDigits(digits) { byte in
            guard let character = Character(Unicode.Scalar(byte)).hexDigitValue else { return false }
            return character < radix
        }
        guard valid else { return nil }
        let clean = String(decoding: digits.filter { $0 != UInt8(ascii: "_") }, as: UTF8.self)
        return Int64(clean, radix: radix).map(TOMLValue.integer)
    }

    private static func scanDigits(in body: ArraySlice<UInt8>, from start: Int) -> Int {
        var end = start
        while end < body.endIndex, isDigit(body[end]) || body[end] == UInt8(ascii: "_") { end += 1 }
        return end
    }

    private static func decimalNumber(_ token: [UInt8]) -> TOMLValue? {
        var body = token[...]
        if let sign = body.first, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { body = body.dropFirst() }
        let integerEnd = scanDigits(in: body, from: body.startIndex)
        let integerPart = body[body.startIndex..<integerEnd]
        guard validDigits(integerPart, isDigit),
              !(integerPart.count > 1 && integerPart.first == UInt8(ascii: "0")) else { return nil }
        var cursor = integerEnd
        var isFloat = false
        if cursor < body.endIndex, body[cursor] == UInt8(ascii: ".") {
            let fractionEnd = scanDigits(in: body, from: cursor + 1)
            guard validDigits(body[(cursor + 1)..<fractionEnd], isDigit) else { return nil }
            cursor = fractionEnd
            isFloat = true
        }
        if cursor < body.endIndex, body[cursor] == UInt8(ascii: "e") || body[cursor] == UInt8(ascii: "E") {
            guard let exponentEnd = scanExponent(in: body, from: cursor + 1) else { return nil }
            cursor = exponentEnd
            isFloat = true
        }
        guard cursor == body.endIndex else { return nil }
        let clean = String(decoding: token.filter { $0 != UInt8(ascii: "_") }, as: UTF8.self)
        if isFloat { return Double(clean).map(TOMLValue.float) }
        return Int64(clean).map(TOMLValue.integer)
    }

    private static func scanExponent(in body: ArraySlice<UInt8>, from start: Int) -> Int? {
        var cursor = start
        if cursor < body.endIndex, body[cursor] == UInt8(ascii: "+") || body[cursor] == UInt8(ascii: "-") {
            cursor += 1
        }
        let end = scanDigits(in: body, from: cursor)
        guard validDigits(body[cursor..<end], isDigit) else { return nil }
        return end
    }
}
