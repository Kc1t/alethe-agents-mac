import Foundation

public enum Feature: String, CaseIterable, Codable, Hashable, Sendable {
    case browser, graphify, mcp, playwright, orchestrator, gsdSync, aiMemory, prs

    public var isOnByDefault: Bool {
        if case .browser = self {
            return true
        } else if case .graphify = self {
            return true
        } else if case .mcp = self {
            return true
        } else if case .prs = self {
            return true
        } else if case .playwright = self {
            return false
        } else if case .orchestrator = self {
            return false
        } else if case .gsdSync = self {
            return false
        } else {
            return false
        }
    }

    public var isSecondary: Bool {
        if case .graphify = self {
            return true
        } else if case .gsdSync = self {
            return true
        } else if case .aiMemory = self {
            return true
        } else if case .browser = self {
            return false
        } else if case .mcp = self {
            return false
        } else if case .playwright = self {
            return false
        } else if case .orchestrator = self {
            return false
        } else {
            return false
        }
    }
}

public struct Features: Hashable, Sendable {
    public private(set) var stored: [String: Bool]

    public static let defaults = Features()

    public init(_ stored: [String: Bool]? = nil) {
        self.stored = stored ?? [:]
    }

    public func isOn(_ feature: Feature) -> Bool {
        stored[feature.rawValue] ?? feature.isOnByDefault
    }

    public mutating func set(_ feature: Feature, on: Bool) {
        stored[feature.rawValue] = on
    }

    public var enabled: [Feature] { Feature.allCases.filter(isOn) }
}

extension PreferencesDocument {
    public var features: Features {
        get { Features(enabledFeatures) }
        set { enabledFeatures = newValue.stored.isEmpty ? nil : newValue.stored }
    }
}
