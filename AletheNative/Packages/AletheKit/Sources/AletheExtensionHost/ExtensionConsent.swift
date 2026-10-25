import Foundation
import AlethePluginKit

public struct ExtensionConsentRecord: Hashable, Sendable, Codable {
    public var bundleIdentifier: String
    public var version: String
    public var granted: Set<PluginCapability>
    public var decidedAt: Date

    public init(bundleIdentifier: String, version: String, granted: Set<PluginCapability>, decidedAt: Date) {
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.granted = granted
        self.decidedAt = decidedAt
    }
}

public enum ExtensionConsentDecision: Equatable, Sendable {
    case allowed
    case promptRequired(Set<PluginCapability>)
    case denied
}

public struct ExtensionConsentLedger: Hashable, Sendable, Codable {
    public private(set) var records: [String: ExtensionConsentRecord]
    public private(set) var denied: Set<String>

    public init() {
        records = [:]
        denied = []
    }

    public func decision(for manifest: PluginManifest) -> ExtensionConsentDecision {
        if denied.contains(manifest.id) { return .denied }
        let granted = records[manifest.id]?.granted ?? []
        let missing = manifest.capabilities.subtracting(granted)
        if records[manifest.id] == nil { return .promptRequired(manifest.capabilities) }
        return missing.isEmpty ? .allowed : .promptRequired(missing)
    }

    public mutating func grant(_ manifest: PluginManifest, at date: Date = Date()) {
        denied.remove(manifest.id)
        records[manifest.id] = ExtensionConsentRecord(
            bundleIdentifier: manifest.id,
            version: manifest.version,
            granted: manifest.capabilities,
            decidedAt: date
        )
    }

    public mutating func deny(_ manifest: PluginManifest) {
        records[manifest.id] = nil
        denied.insert(manifest.id)
    }

    public mutating func forget(_ bundleIdentifier: String) {
        records[bundleIdentifier] = nil
        denied.remove(bundleIdentifier)
    }

    public func isAllowed(_ capability: PluginCapability, for bundleIdentifier: String) -> Bool {
        !denied.contains(bundleIdentifier) && (records[bundleIdentifier]?.granted.contains(capability) ?? false)
    }
}
