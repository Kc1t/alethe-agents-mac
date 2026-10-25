import Foundation

public struct DictationMachine: Equatable, Sendable {
    public enum Failure: String, Equatable, Sendable {
        case microphoneDenied, languageUnsupported, unavailable
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case starting
        case listening
        case finishing
        case failed(Failure)
    }

    public enum Effect: Equatable, Sendable {
        case none, start, stop, cancel
    }

    public static let holdThreshold: TimeInterval = 0.4

    public private(set) var phase = Phase.idle
    private var pressedAt: TimeInterval?

    public init() {}

    public var isActive: Bool { phase == .starting || phase == .listening || phase == .finishing }

    public mutating func keyDown(at now: TimeInterval) -> Effect {
        if phase == .finishing { return .none }
        if phase == .starting || phase == .listening {
            pressedAt = nil
            phase = .finishing
            return .stop
        }
        phase = .starting
        pressedAt = now
        return .start
    }

    public mutating func keyUp(at now: TimeInterval) -> Effect {
        guard let pressed = pressedAt else { return .none }
        pressedAt = nil
        guard now - pressed >= Self.holdThreshold, phase == .starting || phase == .listening else { return .none }
        phase = .finishing
        return .stop
    }

    public mutating func toggle() -> Effect {
        pressedAt = nil
        if phase == .finishing { return .none }
        if phase == .starting || phase == .listening {
            phase = .finishing
            return .stop
        }
        phase = .starting
        return .start
    }

    public mutating func escape() -> Effect {
        pressedAt = nil
        if isActive {
            phase = .idle
            return .cancel
        }
        phase = .idle
        return .none
    }

    public mutating func started() {
        if phase == .starting { phase = .listening }
    }

    public mutating func failed(_ failure: Failure) {
        pressedAt = nil
        phase = .failed(failure)
    }

    public mutating func finished() {
        if phase == .finishing || phase == .listening || phase == .starting { phase = .idle }
    }
}
