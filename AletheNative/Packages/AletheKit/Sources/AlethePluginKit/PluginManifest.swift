import Foundation

public struct PluginAPIVersion: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public var major: Int
    public var minor: Int

    public init(major: Int, minor: Int = 0) {
        self.major = major
        self.minor = minor
    }

    public static let current = PluginAPIVersion(major: 1, minor: 0)

    public func isCompatible(withHost host: PluginAPIVersion = .current) -> Bool {
        major == host.major && minor <= host.minor
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }

    public var description: String { "\(major).\(minor)" }
}

public enum PluginCapability: String, Hashable, Sendable, Codable, CaseIterable {
    case git
    case filesystemRead
    case filesystemWrite
    case terminalInput
    case network
    case storage
}

public struct PluginManifest: Hashable, Sendable, Codable {
    public var id: String
    public var version: String
    public var name: String
    public var capabilities: Set<PluginCapability>
    public var apiVersion: PluginAPIVersion
    public var enabledByDefault: Bool

    public init(
        id: String,
        version: String,
        name: String,
        capabilities: Set<PluginCapability> = [],
        apiVersion: PluginAPIVersion = .current,
        enabledByDefault: Bool = true
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.capabilities = capabilities
        self.apiVersion = apiVersion
        self.enabledByDefault = enabledByDefault
    }

    public var hasValidID: Bool {
        guard let first = id.unicodeScalars.first, id.count <= 128 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")
        let alphanumeric = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        return alphanumeric.contains(first) && id.unicodeScalars.allSatisfy(allowed.contains)
    }
}

@MainActor
public protocol AlethePlugin: AnyObject {
    static var manifest: PluginManifest { get }
    init()
    func activate(context: PluginContext) throws
    func deactivate()
}

extension AlethePlugin {
    public func deactivate() {}
}

public enum PluginError: Error, Equatable, Sendable {
    case undeclaredCapability(PluginCapability, pluginID: String)
    case incompatibleAPI(required: PluginAPIVersion, host: PluginAPIVersion)
    case invalidID(String)
    case duplicatePlugin(String)
    case duplicateContribution(kind: String, id: String)
    case serviceUnavailable(PluginCapability)
    case inactive(pluginID: String)
    case unknownPlugin(String)
}
