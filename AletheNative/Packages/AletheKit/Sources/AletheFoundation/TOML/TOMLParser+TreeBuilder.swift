import Foundation

struct BuildFailure: Error {
    let reason: String
}

struct TOMLTreeBuilder {
    var root = TOMLTable()
    private(set) var current: [TOMLStep] = []
    private var explicit = Set<[TOMLStep]>()
    private var dotted = Set<[TOMLStep]>()
    private var tableArrays = Set<[TOMLStep]>()

    var currentIsArrayScoped: Bool {
        current.contains { if case .index = $0 { return true } else { return false } }
    }

    mutating func openTable(_ path: [String], isArray: Bool) throws {
        var steps: [TOMLStep] = []
        for key in path.dropLast() {
            let parent = try table(at: steps)
            steps.append(.key(key))
            if parent[key] == nil {
                set(.table(TOMLTable()), for: key, in: Array(steps.dropLast()))
            } else if case .table(let table)? = parent[key] {
                if table.style == .inline { throw BuildFailure(reason: "an inline table cannot be extended") }
            } else if case .array(let items)? = parent[key], tableArrays.contains(steps) {
                steps.append(.index(items.count - 1))
            } else {
                throw BuildFailure(reason: "a key already holds a value")
            }
        }
        guard let key = path.last else { throw BuildFailure(reason: "expected a key") }
        let parentSteps = steps
        let existing = try table(at: parentSteps)[key]
        steps.append(.key(key))
        if isArray {
            if existing == nil {
                set(.array([.table(TOMLTable())]), for: key, in: parentSteps)
                tableArrays.insert(steps)
                steps.append(.index(0))
            } else if case .array(var items)? = existing, tableArrays.contains(steps) {
                items.append(.table(TOMLTable()))
                set(.array(items), for: key, in: parentSteps)
                steps.append(.index(items.count - 1))
            } else {
                throw BuildFailure(reason: "a key already holds a value")
            }
        } else {
            if existing == nil {
                set(.table(TOMLTable()), for: key, in: parentSteps)
            } else if case .table(let table)? = existing {
                if table.style == .inline || explicit.contains(steps) || dotted.contains(steps) {
                    throw BuildFailure(reason: "a table is defined twice")
                }
            } else {
                throw BuildFailure(reason: "a key already holds a value")
            }
            explicit.insert(steps)
        }
        current = steps
    }

    mutating func insert(_ key: [String], _ value: TOMLValue) throws {
        var steps = current
        for part in key.dropLast() {
            let parent = try table(at: steps)
            steps.append(.key(part))
            if parent[part] == nil {
                set(.table(TOMLTable()), for: part, in: Array(steps.dropLast()))
                dotted.insert(steps)
            } else if case .table(let table)? = parent[part], table.style == .section && dotted.contains(steps) {
                continue
            } else {
                throw BuildFailure(reason: "a key is defined twice")
            }
        }
        guard let last = key.last else { throw BuildFailure(reason: "expected a key") }
        guard try table(at: steps)[last] == nil else { throw BuildFailure(reason: "a key is defined twice") }
        set(value, for: last, in: steps)
    }

    private func table(at steps: [TOMLStep]) throws -> TOMLTable {
        var table = root
        var rest = steps[...]
        while let step = rest.first {
            rest = rest.dropFirst()
            guard case .key(let key) = step, let child = table[key] else { throw BuildFailure(reason: "internal") }
            if case .index(let position)? = rest.first {
                rest = rest.dropFirst()
                guard case .array(let items) = child, items.indices.contains(position),
                      case .table(let element) = items[position] else { throw BuildFailure(reason: "internal") }
                table = element
            } else {
                guard case .table(let element) = child else { throw BuildFailure(reason: "internal") }
                table = element
            }
        }
        return table
    }

    private mutating func set(_ value: TOMLValue, for key: String, in steps: [TOMLStep]) {
        Self.modify(&root, at: steps[...]) { $0[key] = value }
    }

    private static func modify(_ table: inout TOMLTable, at steps: ArraySlice<TOMLStep>,
                               _ body: (inout TOMLTable) -> Void) {
        guard let step = steps.first else { return body(&table) }
        guard case .key(let key) = step, let child = table[key] else { return }
        var rest = steps.dropFirst()
        if case .index(let position)? = rest.first {
            rest = rest.dropFirst()
            guard case .array(var items) = child, items.indices.contains(position),
                  case .table(var element) = items[position] else { return }
            modify(&element, at: rest, body)
            items[position] = .table(element)
            table[key] = .array(items)
        } else {
            guard case .table(var element) = child else { return }
            modify(&element, at: rest, body)
            table[key] = .table(element)
        }
    }
}
