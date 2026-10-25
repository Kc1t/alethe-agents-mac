import Foundation

public struct PromptHistory: Equatable, Sendable {
    public static let maxTrackedPromptLength = 4 * 1024
    public static let maxEntries = 50

    public private(set) var entries: [String]
    var currentLine = ""
    var overflow = false
    var cursor: Int?
    var escape: Escape = .none

    enum Escape: Equatable, Sendable {
        case none
        case started
        case sequence
    }

    public init(entries: [String] = []) {
        var clean: [String] = []
        for entry in entries {
            let line = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...Self.maxTrackedPromptLength).contains(line.utf16.count),
                  !line.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }),
                  clean.last != line else { continue }
            clean.append(line)
            if clean.count > Self.maxEntries { clean.removeFirst() }
        }
        self.entries = clean
    }

    @discardableResult
    public mutating func record(_ data: String) -> Bool {
        if data.utf16.count > Self.maxTrackedPromptLength {
            currentLine = ""
            overflow = !data.hasSuffix("\r") && !data.hasSuffix("\n")
            return false
        }
        var changed = false
        for character in data {
            if skipEscape(character) { continue }
            if character == "\r" || character == "\n" || character == "\r\n" {
                let line = overflow ? "" : currentLine.trimmingCharacters(in: .whitespaces)
                currentLine = ""
                overflow = false
                cursor = nil
                guard line.utf16.count >= 2, entries.last != line else { continue }
                entries.append(line)
                if entries.count > Self.maxEntries { entries.removeFirst() }
                changed = true
            } else if character == "\u{8}" || character == "\u{7f}" {
                if !overflow, !currentLine.isEmpty { currentLine.removeLast() }
            } else if character == "\u{3}" || character == "\u{15}" {
                currentLine = ""
                overflow = false
                cursor = nil
            } else {
                guard !overflow, let scalar = character.unicodeScalars.first, scalar.value >= 0x20 else { continue }
                if currentLine.utf16.count + String(character).utf16.count <= Self.maxTrackedPromptLength {
                    currentLine.append(character)
                } else {
                    currentLine = ""
                    overflow = true
                }
            }
        }
        return changed
    }

    private mutating func skipEscape(_ character: Character) -> Bool {
        let value = character.unicodeScalars.first?.value ?? 0
        if case .none = escape {
            guard value == 0x1b else { return false }
            escape = .started
        } else if case .started = escape {
            escape = character == "[" || character == "O" ? .sequence : .none
        } else if case .sequence = escape {
            if (0x40...0x7e).contains(value) { escape = .none }
        }
        return true
    }

    public enum Direction: Sendable { case older, newer }

    public mutating func recall(_ direction: Direction) -> String? {
        guard !entries.isEmpty else { return nil }
        var position: Int
        if let cursor {
            position = direction == .older ? cursor - 1 : cursor + 1
        } else {
            position = direction == .older ? entries.count - 1 : entries.count
        }
        position = max(0, min(entries.count, position))
        cursor = position
        let entry = position < entries.count ? entries[position] : ""
        currentLine = entry
        overflow = false
        return entry
    }

    public mutating func reverseSearch(_ query: String) -> String? {
        let end = min(cursor ?? entries.count, entries.count)
        guard end > 0, let index = entries[..<end].lastIndex(where: { $0.contains(query) }) else { return nil }
        cursor = index
        currentLine = entries[index]
        overflow = false
        return currentLine
    }

    public static func recallInput(_ entry: String) -> String { "\u{15}" + entry }
}
