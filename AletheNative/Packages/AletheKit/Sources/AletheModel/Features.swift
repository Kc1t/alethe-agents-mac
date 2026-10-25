import Foundation

public enum Feature: String, CaseIterable, Codable, Hashable, Sendable {
    case browser, graphify, mcp, playwright, orchestrator, gsdSync, aiMemory, prs

    public var isOnByDefault: Bool {
        switch self {
        case .browser, .graphify, .mcp, .prs: true
        case .playwright, .orchestrator, .gsdSync, .aiMemory: false
        }
    }

    public var isSecondary: Bool {
        switch self {
        case .graphify, .gsdSync, .aiMemory: true
        case .browser, .mcp, .playwright, .orchestrator, .prs: false
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
