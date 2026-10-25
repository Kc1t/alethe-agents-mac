import Foundation
import Observation

@Observable
@MainActor
public final class TerminalSearch {
    public internal(set) var isPresented = false
    public internal(set) var needle = ""
    public internal(set) var total: Int?
    public internal(set) var selected: Int?
    public internal(set) var focusRequest = 0

    public enum Status: Equatable, Sendable {
        case none
        case noResults
        case match(position: Int, total: Int)
        case count(Int)
    }

    public var status: Status {
        guard !needle.isEmpty, let total else { return .none }
        if total == 0 { return .noResults }
        if let selected, selected < total { return .match(position: selected + 1, total: total) }
        return .count(total)
    }

    func setNeedle(_ text: String, resetProgress: Bool) -> String {
        let next = Self.bindingNeedle(text)
        if next.isEmpty || (resetProgress && next != needle) {
            total = nil
            selected = nil
        }
        needle = next
        return next
    }

    nonisolated static func bindingNeedle(_ text: String) -> String {
        String(text.prefix { !$0.isNewline }.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
    }
}
