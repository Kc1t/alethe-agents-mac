import Foundation

public enum TOMLValue: Hashable, Sendable {
    case string(String)
    case integer(Int64)
    case float(Double)
    case boolean(Bool)
    case datetime(String)
    case array([TOMLValue])
    case table(TOMLTable)

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var integerValue: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .float(let value) = self {
            return value
        } else if case .integer(let value) = self {
            return Double(value)
        } else {
            return nil
        }
    }

    public var boolValue: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }

    public var arrayValue: [TOMLValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var tableValue: TOMLTable? {
        if case .table(let value) = self { return value }
        return nil
    }

    public var stringArrayValue: [String]? {
        arrayValue?.compactMap(\.stringValue)
    }

    public var tomlText: String { TOMLRender.inline(self) }
}

extension TOMLValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .integer(value) }
    public init(floatLiteral value: Double) { self = .float(value) }
    public init(booleanLiteral value: Bool) { self = .boolean(value) }
    public init(arrayLiteral elements: TOMLValue...) { self = .array(elements) }
}

public struct TOMLTable: Hashable, Sendable, ExpressibleByDictionaryLiteral {
    public enum Style: Hashable, Sendable {
        case section
        case inline
    }

    public var style: Style
    public private(set) var keys: [String] = []
    private var values: [String: TOMLValue] = [:]

    public init(style: Style = .section) {
        self.style = style
    }

    public init(_ entries: [(String, TOMLValue)], style: Style = .section) {
        self.style = style
        for (key, value) in entries { self[key] = value }
    }

    public init(dictionaryLiteral elements: (String, TOMLValue)...) {
        self.init(elements)
    }

    public var isEmpty: Bool { keys.isEmpty }
    public var count: Int { keys.count }

    public var entries: [(key: String, value: TOMLValue)] {
        keys.compactMap { key in values[key].map { (key, $0) } }
    }

    public subscript(key: String) -> TOMLValue? {
        get { values[key] }
        set {
            if let newValue {
                if values.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if values.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    public func value<Path: Collection<String>>(at path: Path) -> TOMLValue? {
        guard let first = path.first else { return .table(self) }
        guard let child = self[first] else { return nil }
        let rest = path.dropFirst()
        if rest.isEmpty { return child }
        guard case .table(let table) = child else { return nil }
        return table.value(at: rest)
    }

    @discardableResult
    public mutating func setValue(_ value: TOMLValue?, at path: ArraySlice<String>,
                                  intermediateStyle: Style = .section) -> Bool {
        guard let first = path.first else { return false }
        let rest = path.dropFirst()
        if rest.isEmpty {
            self[first] = value
            return true
        }
        var child: TOMLTable
        if case .table(let table)? = self[first] {
            child = table
        } else if self[first] == nil {
            guard value != nil else { return false }
            child = TOMLTable(style: intermediateStyle)
        } else {
            return false
        }
        guard child.setValue(value, at: rest, intermediateStyle: intermediateStyle) else { return false }
        self[first] = .table(child)
        return true
    }

    public static func == (lhs: TOMLTable, rhs: TOMLTable) -> Bool {
        lhs.values == rhs.values
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(values)
    }
}

public enum TOMLRender {
    public static func key(_ key: String) -> String {
        let bare = !key.isEmpty && key.utf8.allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
        }
        return bare ? key : string(key)
    }

    public static func keyPath(_ path: [String]) -> String {
        path.map(key).joined(separator: ".")
    }

    private static let stringEscapes: [Unicode.Scalar: String] = [
        "\"": "\\\"", "\\": "\\\\", "\u{08}": "\\b", "\t": "\\t", "\n": "\\n", "\u{0C}": "\\f", "\r": "\\r",
    ]

    public static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            if let escape = stringEscapes[scalar] {
                out += escape
            } else if scalar.value < 0x20 || scalar.value == 0x7F {
                out += String(format: "\\u%04X", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    public static func inline(_ value: TOMLValue) -> String {
        if case .string(let text) = value {
            return string(text)
        } else if case .integer(let number) = value {
            return String(number)
        } else if case .float(let number) = value {
            if number.isNaN { return "nan" }
            if number.isInfinite { return number < 0 ? "-inf" : "inf" }
            let text = String(number)
            return text.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }) ? text : text + ".0"
        } else if case .boolean(let flag) = value {
            return flag ? "true" : "false"
        } else if case .datetime(let text) = value {
            return text
        } else if case .array(let items) = value {
            return "[" + items.map(inline).joined(separator: ", ") + "]"
        }
        guard case .table(let table) = value else { preconditionFailure("Expected TOML table") }
        if table.isEmpty { return "{}" }
        return "{ " + table.entries.map { key($0.key) + " = " + inline($0.value) }.joined(separator: ", ") + " }"
    }
}
