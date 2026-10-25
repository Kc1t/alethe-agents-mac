@_exported import AletheExtensionSDK
import AletheFoundation
import AlethePluginKit
import Foundation

extension ExtensionDescriptor {
    public init(bundleIdentifier: String, payload: ExtensionManifestPayload) {
        self.init(
            bundleIdentifier: bundleIdentifier,
            localizedName: payload.name,
            version: payload.version,
            declaredCapabilities: payload.capabilities,
            apiVersion: PluginAPIVersion(major: payload.apiMajor, minor: payload.apiMinor)
        )
    }
}

public enum ExtensionEnableOutcome: Equatable, Sendable {
    case enabled
    case needsConsent(Set<PluginCapability>)
}

public struct ExtensionHostState: Codable, Equatable, Sendable {
    public private(set) var enabled: Set<String>
    public private(set) var ledger: ExtensionConsentLedger

    public init(enabled: Set<String> = [], ledger: ExtensionConsentLedger = ExtensionConsentLedger()) {
        self.enabled = enabled
        self.ledger = ledger
    }

    public mutating func requestEnable(_ manifest: PluginManifest) -> ExtensionEnableOutcome {
        switch ledger.decision(for: manifest) {
        case .allowed:
            enabled.insert(manifest.id)
            return .enabled
        case .promptRequired(let missing):
            return .needsConsent(missing)
        case .denied:
            ledger.forget(manifest.id)
            return .needsConsent(manifest.capabilities)
        }
    }

    public mutating func approve(_ manifest: PluginManifest, at date: Date = Date()) {
        ledger.grant(manifest, at: date)
        enabled.insert(manifest.id)
    }

    public mutating func decline(_ manifest: PluginManifest) {
        ledger.deny(manifest)
        enabled.remove(manifest.id)
    }

    public mutating func disable(_ bundleIdentifier: String) {
        enabled.remove(bundleIdentifier)
    }

    public func isActive(_ manifest: PluginManifest) -> Bool {
        enabled.contains(manifest.id) && ledger.decision(for: manifest) == .allowed
    }

    public func isAllowed(_ capability: PluginCapability, for bundleIdentifier: String) -> Bool {
        enabled.contains(bundleIdentifier) && ledger.isAllowed(capability, for: bundleIdentifier)
    }

    public static func load(from url: URL) -> ExtensionHostState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(ExtensionHostState.self, from: data) else { return .init() }
        return state
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

public enum ExtensionRequestRouter {
    public static func requiredCapability(for request: HostRequest) -> PluginCapability {
        switch request {
        case .storageGet, .storageSet: .storage
        }
    }

    public static func handle(
        _ request: HostRequest,
        isAllowed: @Sendable (PluginCapability) -> Bool,
        storage: PluginStorage
    ) async -> HostResponse {
        let capability = requiredCapability(for: request)
        guard isAllowed(capability) else { return .denied(capability: capability.rawValue) }
        switch request {
        case .storageGet(let key):
            guard case .string(let value)? = await storage.value(forKey: key) else { return .value(nil) }
            return .value(value)
        case .storageSet(let key, let value):
            await storage.set(value.map(JSONValue.string), forKey: key)
            return .done
        }
    }

    public static func storageID(for bundleIdentifier: String) -> String {
        "ext." + bundleIdentifier.lowercased()
    }
}
